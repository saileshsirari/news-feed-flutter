import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_store/chat_store.dart';
import 'package:chat_store/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mls_crypto/mls_crypto.dart';
import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/api_service.dart';
import 'package:news_feed_flutter/e2e/e2e_device.dart';

class MemorySecrets implements E2eSecrets {
  final keys = <int, Uint8List>{};
  @override
  Future<Uint8List?> read(int userId) async => keys[userId];
  @override
  Future<void> write(int userId, Uint8List key) async => keys[userId] = key;
}

/// Stands in for the Rust library: a device is its identity plus a counter
/// of packages made, and its "sealed" state is that, base64'd with the key.
class FakeMls implements MlsDevice {
  FakeMls(this._identity, [this.made = 0]);
  final List<int> _identity;
  int made;

  static Future<MlsDevice> create(List<int> identity) async => FakeMls(identity);

  static Future<MlsDevice> restore(List<int> sealed, List<int> key) async {
    final json = jsonDecode(utf8.decode(sealed)) as Map<String, dynamic>;
    if (json['key'] != base64Encode(key)) throw const MlsException('wrong key');
    return FakeMls(utf8.encode(json['identity'] as String), json['made'] as int);
  }

  @override
  Future<Uint8List> snapshot(List<int> key) async =>
      utf8.encode(jsonEncode({'identity': utf8.decode(_identity), 'made': made, 'key': base64Encode(key)}));

  @override
  Future<Uint8List> identity() async => Uint8List.fromList(_identity);

  @override
  Future<Uint8List> keyPackage() async => utf8.encode('kp-${++made}');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late ChatDatabase db;
  late MessageStore store;
  late MemorySecrets secrets;
  late List<String> uploads;
  late int serverCount;

  setUp(() {
    db = inMemoryChatDatabase();
    store = MessageStore(db);
    secrets = MemorySecrets();
    uploads = [];
    serverCount = 0;
  });

  tearDown(() => db.close());

  E2eDevice manager() => E2eDevice(
        userId: 2004,
        store: store,
        secrets: secrets,
        create: FakeMls.create,
        restore: FakeMls.restore,
        api: ApiService(
          AppConfig(apiBaseUrl: Uri.parse('https://example.test')),
          httpClient: MockClient((request) async {
            if (request.url.path == '/e2e/key-packages/count') return http.Response(jsonEncode({'count': serverCount}), 200);
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final packages = (body['keyPackages'] as List).cast<String>();
            uploads.add('${packages.length}${body['replace'] == true ? ' replace' : ''}');
            serverCount = (body['replace'] == true ? 0 : serverCount) + packages.length;
            return http.Response(jsonEncode({'count': serverCount}), 201);
          }),
        ),
      );

  test('first time: makes an identity, saves it sealed, uploads a full batch replacing old ones', () async {
    await manager().ensureKeyPackages(5);
    expect(uploads, ['50 replace']);
    expect(utf8.decode(await (await manager().device(5)).identity()), 'user:2004/device:5');
    expect(secrets.keys[2004], hasLength(32));
    expect(await store.blob('e2e_state'), isNotNull);
  });

  test('later starts: restores the same identity, tops up only when low', () async {
    await manager().ensureKeyPackages(5);
    await manager().ensureKeyPackages(5); // 50 on the server: nothing to do
    serverCount = 12; // others used 38
    await manager().ensureKeyPackages(5);
    expect(uploads, ['50 replace', '38']);
    // The packages made before were saved: the counter carried on, no repeats.
    final restored = await manager().device(5) as FakeMls;
    expect(restored.made, 88);
  });

  test('a lost state key means a new identity, and its packages replace the old', () async {
    await manager().ensureKeyPackages(5);
    secrets.keys[2004] = Uint8List(32); // secure storage was reset
    await manager().ensureKeyPackages(5);
    expect(uploads, ['50 replace', '50 replace']);
  });
}
