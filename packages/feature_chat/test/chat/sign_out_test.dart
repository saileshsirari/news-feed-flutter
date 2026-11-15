import 'dart:convert';

import 'package:app_core/app_core.dart';
import 'package:app_core/config/app_config.dart';
import 'package:app_core/data/services/api_service.dart';
import 'package:app_core/data/services/service_providers.dart';
import 'package:app_core/session/current_user_provider.dart';
import 'package:chat_store/chat_store.dart';
import 'package:chat_store/testing.dart';
import 'package:feature_chat/chat/local/local_chat.dart';
import 'package:feature_chat/feature_chat.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chat's part of logging out (ChatMiniApp.onSignOut, called by the
/// session for every loaded mini-app).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig(apiBaseUrl: Uri.parse('http://127.0.0.1:9'));
  const celebrity = {'id': 7, 'username': 'celebrity', 'created_at': 0, 'followerCount': 1000};

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('logout works with chat history on the device, and deletes it', () async {
    final api = ApiService(
      config,
      httpClient: MockClient((request) async => http.Response(jsonEncode(celebrity), 200)),
    );
    // One in-memory database we keep a handle on, to look inside afterwards.
    final db = inMemoryChatDatabase();
    addTearDown(db.close);
    final container = ProviderContainer.test(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        apiServiceProvider.overrideWithValue(api),
        chatDatabaseProvider.overrideWith((ref, userId) => db),
        miniAppSlotsProvider.overrideWithValue([MiniAppSlot.eager(ChatMiniApp())]),
      ],
    );
    await container.read(currentUserProvider.future);
    await container.read(currentUserProvider.notifier).login('celebrity');
    // Chat history on the device, as after opening a chat.
    final store = container.read(messageStoreProvider(7));
    await store.upsertAll([
      remoteMessageFrom({
        'id': 1,
        'conversation_id': 5,
        'seq': 1,
        'sender_id': 2,
        'body': 'hi',
        'created_at': 0,
        'sender_username': 'ann',
      }),
    ]);

    await container.read(currentUserProvider.notifier).logout();

    expect(container.read(currentUserProvider).value, isNull);
    expect(await MessageStore(db).search('hi'), isEmpty);
  });
}
