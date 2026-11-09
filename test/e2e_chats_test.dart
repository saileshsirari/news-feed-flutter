import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chat_store/chat_store.dart';
import 'package:chat_store/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mls_crypto/mls_crypto.dart';
import 'package:news_feed_flutter/chat/local/local_chat.dart';
import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/api_service.dart';
import 'package:news_feed_flutter/e2e/e2e_chats.dart';
import 'package:news_feed_flutter/e2e/e2e_device.dart';
import 'package:news_feed_flutter/models/models.dart';
import 'package:shared_media/shared_media.dart';

/// The real Rust library, built for this computer (see packages/mls_crypto/README).
const _library = 'packages/mls_crypto/rust/target/release/libmls_crypto.dylib';

class MemorySecrets implements E2eSecrets {
  final keys = <int, Uint8List>{};
  @override
  Future<Uint8List?> read(int userId) async => keys[userId];
  @override
  Future<void> write(int userId, Uint8List key) async => keys[userId] = key;
}

/// Just enough of the server for one 1:1 chat (conversation 5 between users
/// 1 and 2): key packages, turning encryption on, welcomes, and messages
/// numbered by seq with the epoch rule. Requests say who's calling.
class FakeServer {
  final devices = <int, List<int>>{1: [11, 12], 2: [21]};
  final keyPackages = <int, List<String>>{}; // device -> base64 packages
  final messages = <Map<String, dynamic>>[];
  final welcomes = <Map<String, dynamic>>[];
  var encryption = 'server';
  String? groupId;
  var epoch = 0;
  var nextId = 1000;

  Map<String, dynamic> _message(
    int sender,
    String mode, {
    String body = '',
    String? ciphertext,
    int? device,
    List<int> mediaIds = const [],
  }) {
    final m = {
      'id': nextId++,
      'conversation_id': 5,
      'seq': messages.length + 1,
      'sender_id': sender,
      'sender_username': 'user$sender',
      'body': body,
      'created_at': messages.length + 1,
      'mode': mode,
      'ciphertext': ciphertext,
      'sender_device_id': device,
      // As the server lists an encrypted message's files: just bytes, and a link.
      'media': [
        for (final id in mediaIds)
          {'id': id, 'kind': 'encrypted', 'contentType': 'application/octet-stream', 'sizeBytes': 1, 'url': 'https://bucket.test/$id'},
      ],
      'reactions': [],
    };
    messages.add(m);
    return m;
  }

  http.Client clientFor(int user) => MockClient((request) async {
        final path = request.url.path;
        final q = request.url.queryParameters;
        Map<String, dynamic> body() => jsonDecode(request.body) as Map<String, dynamic>;
        http.Response json(Object o, [int status = 200]) => http.Response.bytes(
              utf8.encode(jsonEncode(o)),
              status,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );

        if (path == '/e2e/key-packages/count') return json({'count': keyPackages[int.parse(q['deviceId']!)]?.length ?? 0});
        if (path == '/e2e/key-packages') {
          final b = body();
          final list = keyPackages.putIfAbsent(b['deviceId'] as int, () => []);
          if (b['replace'] == true) list.clear();
          list.addAll((b['keyPackages'] as List).cast<String>());
          return json({'count': list.length}, 201);
        }
        if (path == '/e2e/key-packages/claim') {
          final out = <Map<String, dynamic>>[];
          for (final u in (body()['userIds'] as List).cast<int>().toSet()) {
            for (final d in devices[u]!) {
              final list = keyPackages[d] ?? [];
              if (list.isNotEmpty) out.add({'userId': u, 'deviceId': d, 'keyPackage': list.removeAt(0)});
            }
          }
          return json({'keyPackages': out, 'missing': []});
        }
        if (path == '/conversations/5/e2e') {
          if (encryption == 'e2e') return json({'error': 'already'}, 409);
          final b = body();
          encryption = 'e2e';
          groupId = b['groupId'] as String;
          epoch = b['epoch'] as int;
          final notice = _message(user, 'notice', body: '🔒 End-to-end encryption turned on', device: b['deviceId'] as int);
          for (final r in b['recipients'] as List) {
            welcomes.add({
              'id': welcomes.length + 1,
              'device_id': (r as Map)['deviceId'],
              'conversation_id': 5,
              'welcome': b['welcome'],
              'after_seq': notice['seq'],
              'mls_group_id': groupId,
            });
          }
          return json({'seq': notice['seq']}, 201);
        }
        if (path == '/e2e/welcomes' && request.method == 'GET') {
          return json([for (final w in welcomes) if (w['device_id'] == int.parse(q['deviceId']!)) w]);
        }
        if (path.startsWith('/e2e/welcomes/')) {
          welcomes.removeWhere((w) => w['id'] == int.parse(request.url.pathSegments.last));
          return http.Response('', 204);
        }
        if (path == '/conversations/5/messages/encrypted') {
          final b = body();
          if (b['epoch'] != epoch) return json({'error': 'stale', 'currentEpoch': epoch}, 409);
          if (b['changesGroup'] == true) epoch++;
          return json(
            _message(user, b['changesGroup'] == true ? 'commit' : 'e2e',
                ciphertext: b['ciphertext'] as String,
                device: b['deviceId'] as int,
                mediaIds: [...?(b['mediaIds'] as List?)?.cast<int>()]),
            201,
          );
        }
        if (path == '/conversations/5/messages') {
          final limit = int.parse(q['limit'] ?? '50');
          final List<Map<String, dynamic>> page;
          if (q['afterSeq'] != null) {
            page = messages.where((m) => (m['seq'] as int) > int.parse(q['afterSeq']!)).take(limit).toList();
            final more = messages.where((m) => (m['seq'] as int) > int.parse(q['afterSeq']!)).length > limit;
            return json({'messages': page, 'hasMore': more});
          }
          final before = int.parse(q['beforeSeq'] ?? '9007199254740991');
          page = messages.where((m) => (m['seq'] as int) < before).toList().reversed.take(limit).toList();
          return json({'messages': page, 'hasMore': false});
        }
        return http.Response('{}', 404);
      });
}

/// One device: its own database, keys and engine.
class Device {
  Device(this.user, this.deviceId, FakeServer server) {
    db = inMemoryChatDatabase();
    store = MessageStore(db);
    api = ApiService(AppConfig(apiBaseUrl: Uri.parse('https://example.test')), httpClient: server.clientFor(user));
    keys = E2eDevice(userId: user, store: store, secrets: MemorySecrets(), api: api);
    chats = E2eChats(userId: user, api: api, store: store, e2eDevice: keys, deviceIdOf: () async => deviceId);
    sync = ChatSync(store, ApiMessageSource(api, user));
  }

  final int user;
  final int deviceId;
  late final ChatDatabase db;
  late final MessageStore store;
  late final ApiService api;
  late final E2eDevice keys;
  late final E2eChats chats;
  late final ChatSync sync;

  /// What this device shows in chat 5, oldest first.
  Future<List<String>> shown() async => [
        for (final row in await store.watchFrom(5, 0).first)
          if (chatMessageFrom(row) case final m when !m.isGroupChange) m.body,
      ];
}

void main() {
  setUpAll(() async {
    if (!File(_library).existsSync()) {
      fail('Build the Rust library first: cd packages/mls_crypto/rust && cargo build --release');
    }
    await initMlsCrypto(libraryPath: _library);
  });

  late FakeServer server;
  late Device alicePhone, aliceWeb, bobPhone;

  setUp(() async {
    server = FakeServer();
    alicePhone = Device(1, 11, server);
    aliceWeb = Device(1, 12, server);
    bobPhone = Device(2, 21, server);
    for (final d in [alicePhone, aliceWeb, bobPhone]) {
      await d.keys.ensureKeyPackages(d.deviceId);
    }
  });

  tearDown(() async {
    for (final d in [alicePhone, aliceWeb, bobPhone]) {
      await d.db.close();
    }
  });

  final chat = ConversationSummary(id: 5, isGroup: false, otherUserId: 2, unreadCount: 0);

  test('turned on, then read and written on every device, each with real MLS', () async {
    await alicePhone.chats.turnOn(chat, [1, 2]);
    expect(server.encryption, 'e2e');
    expect(server.welcomes.map((w) => w['device_id']).toSet(), {12, 21}); // everyone else

    for (final d in [aliceWeb, bobPhone]) {
      await d.chats.joinWelcomes();
      expect(await d.chats.canRead(5), isTrue);
    }

    await alicePhone.chats.send(5, 'hi bob 👋', clientMessageId: 'c1');
    // What the server holds is not the text.
    expect(utf8.decode(base64Decode(server.messages.last['ciphertext'] as String), allowMalformed: true),
        isNot(contains('hi bob')));

    await bobPhone.chats.sync(5);
    await aliceWeb.chats.sync(5); // Alice's other device reads it too
    await alicePhone.chats.sync(5); // and her phone doesn't trip over its own
    for (final d in [alicePhone, aliceWeb, bobPhone]) {
      expect(await d.shown(), ['🔒 End-to-end encryption turned on', 'hi bob 👋']);
    }

    await bobPhone.chats.send(5, 'hey!', clientMessageId: 'c2');
    await alicePhone.chats.sync(5);
    await aliceWeb.chats.sync(5);
    expect(await alicePhone.shown(), ['🔒 End-to-end encryption turned on', 'hi bob 👋', 'hey!']);
    expect(await aliceWeb.shown(), ['🔒 End-to-end encryption turned on', 'hi bob 👋', 'hey!']);
  });

  test('the general sync never overwrites decrypted text, and placeholders get replaced', () async {
    await alicePhone.chats.turnOn(chat, [1, 2]);
    await bobPhone.chats.joinWelcomes();
    await alicePhone.chats.send(5, 'one', clientMessageId: 'c1');

    // Bob's screen opens first: the newest page arrives as placeholders...
    await bobPhone.sync.syncLatest(5);
    expect((await bobPhone.shown()).last, encryptedPlaceholder);
    // ...then the engine decrypts in order and replaces them.
    await bobPhone.chats.sync(5);
    expect((await bobPhone.shown()).last, 'one');
    // A later page refresh brings the ciphertext again: it changes nothing.
    await bobPhone.sync.syncLatest(5);
    await bobPhone.sync.refreshStale(5, 1, 99, maxAge: Duration.zero);
    expect((await bobPhone.shown()).last, 'one');
  });

  test('saved and restored mid-chat (an app restart), a device keeps reading', () async {
    await alicePhone.chats.turnOn(chat, [1, 2]);
    await bobPhone.chats.joinWelcomes();
    await alicePhone.chats.send(5, 'before', clientMessageId: 'c1');
    await bobPhone.chats.sync(5);

    // Bob's app restarts: same database and secrets, a fresh engine.
    final restarted = E2eDevice(userId: 2, store: bobPhone.store, secrets: bobPhone.keys.secrets, api: bobPhone.api);
    final engine = E2eChats(userId: 2, api: bobPhone.api, store: bobPhone.store, e2eDevice: restarted, deviceIdOf: () async => 21);
    await alicePhone.chats.send(5, 'after', clientMessageId: 'c2');
    await engine.sync(5);
    expect(await bobPhone.shown(), ['🔒 End-to-end encryption turned on', 'before', 'after']);
  });

  test('a photo\'s key goes inside the encrypted message; every device gets it, the server doesn\'t', () async {
    await alicePhone.chats.turnOn(chat, [1, 2]);
    await bobPhone.chats.joinWelcomes();
    final key = Uint8List.fromList(List.generate(32, (i) => i + 100));
    final photo = SealedAttachment(
      mediaId: 77,
      key: key,
      kind: MediaKind.image,
      contentType: 'image/jpeg',
      sizeBytes: 1234,
      width: 4,
      height: 3,
      preview: Uint8List.fromList([1, 2, 3]),
    );

    final sent = await alicePhone.chats.send(5, 'look', clientMessageId: 'c1', media: [photo]);
    expect(sent.sealedMedia.single.key, key);
    expect(sent.media, isEmpty); // the server's copy is bytes, not something to show
    final stored = server.messages.last;
    expect((stored['media'] as List).single['id'], 77);
    expect(base64Decode(stored['ciphertext'] as String), isNot(containsAllInOrder(key.sublist(0, 8))));

    await bobPhone.chats.sync(5);
    final received = chatMessageFrom((await bobPhone.store.watchFrom(5, 0).first).last);
    expect(received.body, 'look');
    final file = received.sealedMedia.single;
    expect((file.mediaId, file.contentType, file.width), (77, 'image/jpeg', 4));
    expect(file.key, key);
    expect(file.preview, [1, 2, 3]);
  });

  test('previews ride along only while they fit; the rest come without', () {
    SealedAttachment withPreview(int id, int size) => SealedAttachment(
          mediaId: id,
          key: Uint8List(32),
          kind: MediaKind.image,
          contentType: 'image/jpeg',
          sizeBytes: 1,
          preview: Uint8List(size),
        );
    final kept = E2eChats.previewsWithinBudget([withPreview(1, 10000), withPreview(2, 20000), withPreview(3, 9000)]);
    expect(kept.map((m) => m.preview?.length), [10000, null, 9000]);
  });

  test('only one person can turn it on; a second try is refused', () async {
    await alicePhone.chats.turnOn(chat, [1, 2]);
    await expectLater(
      bobPhone.chats.turnOn(ConversationSummary(id: 5, isGroup: false, otherUserId: 1, unreadCount: 0), [2, 1]),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
    );
  });

  test('a test account (no device) can\'t turn it on', () async {
    final noDevice = E2eChats(
      userId: 1,
      api: alicePhone.api,
      store: alicePhone.store,
      e2eDevice: alicePhone.keys,
      deviceIdOf: () async => null,
    );
    await expectLater(noDevice.turnOn(chat, [1, 2]), throwsA(isA<E2eUnavailable>()));
  });
}
