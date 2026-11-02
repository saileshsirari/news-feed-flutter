import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/chat/contacts_notifier.dart';
import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/api_service.dart';
import 'package:news_feed_flutter/data/services/service_providers.dart';
import 'package:news_feed_flutter/session/current_user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> user(int id) => {'id': id, 'username': 'user_$id', 'created_at': 0};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // POST /conversations bodies the fake server received.
  late List<Map<String, dynamic>> created;

  setUp(() {
    // Logged in as user 1.
    SharedPreferences.setMockInitialValues({'id': 1, 'username': 'user_1', 'followerCount': 0});
    created = [];
  });

  Future<(ProviderContainer, ProviderSubscription<ContactsState>)> open() async {
    final api = ApiService(
      AppConfig(apiBaseUrl: Uri.parse('https://example.test')),
      httpClient: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(jsonEncode([user(1), user(2), user(3), user(4)]), 200);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        created.add(body);
        return http.Response(jsonEncode({'id': 50, 'is_group': body['isGroup'], 'name': body['name']}), 200);
      }),
    );
    final container = ProviderContainer.test(overrides: [apiServiceProvider.overrideWithValue(api)]);
    await container.read(currentUserProvider.future);
    final sub = container.listen(contactsProvider, (_, _) {});
    await pumpEventQueue();
    return (container, sub);
  }

  test('lists everyone except the current user', () async {
    final (_, sub) = await open();

    expect(sub.read().isLoading, isFalse);
    expect(sub.read().contacts.map((u) => u.id), [2, 3, 4]);
  });

  test('selection: toggling mode clears picks, toggling a row adds then removes it', () async {
    final (container, sub) = await open();
    final notifier = container.read(contactsProvider.notifier);

    notifier.toggleSelectionMode();
    notifier.toggleSelected(2);
    notifier.toggleSelected(3);
    notifier.toggleSelected(2);
    expect(sub.read().selectedUserIds, {3});

    final before = sub.read();
    notifier.toggleSelected(4);
    // A new state with a new Set; the old state was not changed in place.
    expect(before.selectedUserIds, {3});
    expect(sub.read().selectedUserIds, {3, 4});

    notifier.toggleSelectionMode();
    expect(sub.read().selectionMode, isFalse);
    expect(sub.read().selectedUserIds, isEmpty);
  });

  test('openDirectConversation creates a 1:1 with the current user and returns its id', () async {
    final (container, sub) = await open();

    final id = await container.read(contactsProvider.notifier).openDirectConversation(sub.read().contacts.first);

    expect(id, 50);
    expect(created.single, {'participantIds': [1, 2], 'isGroup': false});
  });

  test('createGroup with no name falls back to the members, then leaves selection mode', () async {
    final (container, sub) = await open();
    final notifier = container.read(contactsProvider.notifier)
      ..toggleSelectionMode()
      ..toggleSelected(2)
      ..toggleSelected(3);

    final conversation = await notifier.createGroup('  ');

    expect(conversation.name, 'user_2, user_3');
    expect(created.single['participantIds'], [1, 2, 3]);
    expect(sub.read().selectionMode, isFalse);
    expect(sub.read().selectedUserIds, isEmpty);
  });
}
