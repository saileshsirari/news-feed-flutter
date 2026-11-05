import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/chat/conversation_notifier.dart';
import 'package:news_feed_flutter/chat/message_sender.dart';
import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/api_service.dart';
import 'package:news_feed_flutter/data/services/service_providers.dart';
import 'package:news_feed_flutter/data/services/socket_provider.dart';
import 'package:news_feed_flutter/models/models.dart';
import 'package:news_feed_flutter/session/current_user_provider.dart';
import 'package:shared_media/shared_media.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_chat_server.dart';
import '../helpers/fake_socket.dart';

/// Ids 10, 11, 12, ... are seqs 1, 2, 3, ... in conversation 5.
Map<String, dynamic> message(int id, {int senderId = 2, String body = 'hi'}) => {
      'id': id,
      'conversation_id': 5,
      'seq': id - 9,
      'sender_id': senderId,
      'body': body,
      'created_at': id,
      'sender_username': 'user_$senderId',
    };

Map<String, dynamic> message12() => message(12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig(apiBaseUrl: Uri.parse('https://example.test'));

  late FakeSocket socket;
  // What the fake server currently has.
  late List<Map<String, dynamic>> serverMessages;
  late List<http.Request> requests;
  // How many POSTs fail with a dropped connection before one gets through.
  late int failingPosts;
  // The server answers nothing (offline).
  late bool offline;

  setUp(() {
    failingPosts = 0;
    offline = false;
    retryDelay = Duration.zero;
    // Logged in as user 1 (UserSession reads these keys).
    SharedPreferences.setMockInitialValues({'id': 1, 'username': 'user_0', 'followerCount': 0});
    socket = FakeSocket();
    serverMessages = [message(11), message(10)];
    requests = [];
  });

  /// A container where conversation 5 is backed by the fake server above.
  Future<ProviderContainer> openContainer() async {
    final api = ApiService(
      config,
      httpClient: MockClient((request) async {
        requests.add(request);
        if (offline) throw http.ClientException('offline');
        final path = request.url.path;
        if (request.method == 'GET' && path == '/conversations/5/messages') {
          return answerMessagesBySeq(request, serverMessages);
        }
        if (request.method == 'GET' && path == '/conversations/5/reads') {
          return http.Response(
            jsonEncode([
              {'user_id': 1, 'last_read_message_id': 11},
              {'user_id': 2, 'last_read_message_id': 10},
            ]),
            200,
          );
        }
        if (request.method == 'POST' && path == '/conversations/5/messages') {
          if (failingPosts > 0) {
            failingPosts--;
            throw http.ClientException('Connection reset by peer');
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final sent = message(12, senderId: 1, body: body['body'] as String);
          serverMessages = [...serverMessages.where((m) => m['id'] != 12), sent];
          return http.Response(jsonEncode(sent), 200);
        }
        return http.Response('{}', 200); // PUT /read
      }),
    );
    final container = ProviderContainer.test(overrides: [
      apiServiceProvider.overrideWithValue(api),
      socketProvider.overrideWith((ref, userId) => socket),
      ...localChatOverrides(),
    ]);
    await container.read(currentUserProvider.future);
    return container;
  }

  /// Watches conversation 5 (like the open screen does) and lets its
  /// initial requests finish.
  Future<ProviderSubscription<ConversationState>> open(ProviderContainer container) async {
    final sub = container.listen(conversationProvider(5), (_, _) {});
    await pumpEventQueue();
    return sub;
  }

  test('starts loading, then shows messages oldest-first', () async {
    final container = await openContainer();
    final sub = container.listen(conversationProvider(5), (_, _) {});

    expect(sub.read().isLoading, isTrue);

    await pumpEventQueue();
    expect(sub.read().isLoading, isFalse);
    expect(sub.read().messages.map((m) => m.id), [10, 11]);
  });

  test('history on the device shows even when the server can\'t be reached', () async {
    final container = await openContainer();
    final first = await open(container);
    first.close();
    await container.pump(); // the screen closed

    offline = true;
    final again = await open(container);
    expect(again.read().messages.map((m) => m.id), [10, 11]);
    expect(again.read().error, isNull);
  });

  test('scrolling up loads older pages until the first message', () async {
    serverMessages = [for (var id = 10; id < 130; id++) message(id)]; // seqs 1..120
    final container = await openContainer();
    final sub = await open(container);
    expect(sub.read().messages.length, 50); // the newest page
    expect(sub.read().messages.first.seq, 71);
    expect(sub.read().reachedStart, isFalse);

    final notifier = container.read(conversationProvider(5).notifier);
    await notifier.loadOlder();
    await pumpEventQueue();
    expect(sub.read().messages.first.seq, 21);

    await notifier.loadOlder();
    await pumpEventQueue();
    expect(sub.read().messages.first.seq, 1);
    expect(sub.read().messages.length, 120);
    expect(sub.read().reachedStart, isTrue);
  });

  test('read states drive the Seen tick', () async {
    final container = await openContainer();
    final sub = await open(container);

    // user 2 has read up to 10, not 11.
    expect(sub.read().isReadByOthers(10, currentUserId: 1), isTrue);
    expect(sub.read().isReadByOthers(11, currentUserId: 1), isFalse);

    socket.controller.add({'type': 'read_receipt_updated', 'conversationId': 5, 'userId': 2, 'lastReadMessageId': 11});
    await pumpEventQueue();

    expect(sub.read().isReadByOthers(11, currentUserId: 1), isTrue);
  });

  test('message_created for this conversation fetches what is missing; other conversations are ignored', () async {
    final container = await openContainer();
    final sub = await open(container);
    serverMessages = [message(13), ...serverMessages];

    socket.controller.add({'type': 'message_created', 'conversationId': 99, 'seq': 1});
    await pumpEventQueue();
    expect(sub.read().messages.map((m) => m.id), [10, 11]);

    requests.clear();
    socket.controller.add({'type': 'message_created', 'conversationId': 5, 'seq': 4});
    await pumpEventQueue();
    // Only after seq 2: 12 (seq 3) never existed here, 13 is seq 4.
    expect(requests.first.url.queryParameters['afterSeq'], '2');
    expect(sub.read().messages.map((m) => m.id), [10, 11, 13]);
    // ...and marks the new newest message read.
    expect(requests.last.method, 'PUT');
    expect(jsonDecode(requests.last.body)['lastReadMessageId'], 13);
  });

  test('after a reconnect, reloads messages missed while disconnected', () async {
    final container = await openContainer();
    final sub = await open(container);
    serverMessages = [message(14), ...serverMessages]; // arrived while the socket was down

    socket.controller.add({'type': 'reconnected'});
    await pumpEventQueue();

    expect(sub.read().messages.map((m) => m.id), [10, 11, 14]);
  });

  test('send appends the sent message', () async {
    final container = await openContainer();
    final sub = await open(container);

    final sending = container.read(conversationProvider(5).notifier).send('  hello  ');
    expect(sub.read().isSending, isTrue);
    await sending;
    await pumpEventQueue(); // the list follows the database

    expect(sub.read().isSending, isFalse);
    expect(sub.read().messages.last.body, 'hello');
  });

  test('closing the screen disposes the notifier and stops listening to the socket', () async {
    final container = await openContainer();
    final sub = await open(container);
    expect(socket.controller.hasListener, isTrue);

    sub.close();
    await container.pump(); // let autoDispose run

    expect(socket.controller.hasListener, isFalse);
  });

  List<Map<String, dynamic>> posts() => [
        for (final r in requests)
          if (r.method == 'POST') jsonDecode(r.body) as Map<String, dynamic>,
      ];

  test('each send carries a client id, different for every message', () async {
    final container = await openContainer();
    await open(container);
    final notifier = container.read(conversationProvider(5).notifier);
    await notifier.send('one');
    await notifier.send('two');

    final ids = posts().map((p) => p['clientMessageId'] as String).toList();
    expect(ids, hasLength(2));
    expect(ids[0], isNot(ids[1]));
    expect(ids, everyElement(matches(RegExp(r'^[\w-]{1,64}$'))));
  });

  test('a dropped connection is retried once with the same client id', () async {
    final container = await openContainer();
    final sub = await open(container);
    failingPosts = 1;

    await container.read(conversationProvider(5).notifier).send('hello');
    await pumpEventQueue();

    expect(posts(), hasLength(2));
    expect(posts()[1]['clientMessageId'], posts()[0]['clientMessageId']);
    expect(sub.read().messages.last.body, 'hello');
    expect(sub.read().error, isNull);
  });

  test('gives up after the retry fails too, and says so', () async {
    final container = await openContainer();
    final sub = await open(container);
    failingPosts = 2;

    await container.read(conversationProvider(5).notifier).send('hello');

    expect(posts(), hasLength(2));
    expect(sub.read().error, startsWith('Couldn\'t send'));
    expect(sub.read().isSending, isFalse);
  });

  test('reads a message\'s photos and videos from the server', () {
    final message = ChatMessage.fromJson({
      ...message12(),
      'media': [
        {'id': 3, 'kind': 'video', 'contentType': 'video/mp4', 'sizeBytes': 9, 'durationMs': 4000, 'url': 'https://b.test/3'},
        {'id': 1, 'kind': 'image', 'contentType': 'image/jpeg', 'sizeBytes': 5, 'url': 'https://b.test/1'},
      ],
    });
    expect(message.media.map((m) => m.id), [3, 1]);
    expect(message.media.first.kind, MediaKind.video);
    expect(ChatMessage.fromJson(message12()).media, isEmpty);
  });
}
