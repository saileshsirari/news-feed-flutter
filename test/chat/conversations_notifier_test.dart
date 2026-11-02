import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/chat/conversations_notifier.dart';
import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/api_service.dart';
import 'package:news_feed_flutter/data/services/service_providers.dart';
import 'package:news_feed_flutter/data/services/socket_provider.dart';
import 'package:news_feed_flutter/session/current_user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_socket.dart';

Map<String, dynamic> conversation(int id, {int unread = 0}) => {
      'id': id,
      'is_group': false,
      'name': null,
      'other_username': 'user_$id',
      'last_message_body': 'hi',
      'last_message_created_at': id,
      'unread_count': unread,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSocket socket;
  // What the fake server returns for GET /conversations, and how often it was asked.
  late List<Map<String, dynamic>> serverConversations;
  late int fetches;
  late bool failNext;

  setUp(() {
    SharedPreferences.setMockInitialValues({'id': 1, 'username': 'user_0', 'followerCount': 0});
    socket = FakeSocket();
    serverConversations = [conversation(2, unread: 3)];
    fetches = 0;
    failNext = false;
  });

  /// Logged in as user 1, watching the Chat tab's provider like the screen does.
  Future<(ProviderContainer, ProviderSubscription<ConversationsState>)> open() async {
    final api = ApiService(
      AppConfig(apiBaseUrl: Uri.parse('https://example.test')),
      httpClient: MockClient((request) async {
        fetches++;
        if (failNext) return http.Response('boom', 500);
        return http.Response(jsonEncode(serverConversations), 200);
      }),
    );
    final container = ProviderContainer.test(overrides: [
      apiServiceProvider.overrideWithValue(api),
      socketProvider.overrideWith((ref, userId) => socket),
    ]);
    await container.read(currentUserProvider.future);
    final sub = container.listen(conversationsProvider, (_, _) {});
    return (container, sub);
  }

  test('starts loading, then shows the conversations', () async {
    final (_, sub) = await open();
    expect(sub.read().isLoading, isTrue);

    await pumpEventQueue();

    expect(sub.read().isLoading, isFalse);
    expect(sub.read().conversations.single.unreadCount, 3);
  });

  test('reloads on each reload-trigger socket event, ignores others', () async {
    final (_, sub) = await open();
    await pumpEventQueue();
    expect(fetches, 1);

    socket.controller.add({'type': 'feed_updated'});
    await pumpEventQueue();
    expect(fetches, 1);

    serverConversations = [conversation(3), conversation(2, unread: 4)];
    for (final type in ['conversations_changed', 'message_created', 'read_receipt_updated']) {
      socket.controller.add({'type': type});
      await pumpEventQueue();
    }
    expect(fetches, 4);
    expect(sub.read().conversations.map((c) => c.id), [3, 2]);
  });

  test('a failed load shows an error, and the next load clears it', () async {
    failNext = true;
    final (container, sub) = await open();
    await pumpEventQueue();
    expect(sub.read().error, contains('Couldn\'t load conversations'));

    failNext = false;
    await container.read(conversationsProvider.notifier).load();

    expect(sub.read().error, isNull);
    expect(sub.read().conversations, hasLength(1));
  });
}
