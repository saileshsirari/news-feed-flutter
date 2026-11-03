import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/api_service.dart';
import 'package:news_feed_flutter/data/services/service_providers.dart';
import 'package:news_feed_flutter/data/services/socket_provider.dart';
import 'package:news_feed_flutter/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_socket.dart';

/// The whole app against a fake server: every screen and notifier builds
/// for real, so a mistake that only shows up when widgets mount (not in a
/// notifier test on its own) fails here.
void main() {
  testWidgets('log in, see the feed, open chats, log out', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final socket = FakeSocket();
    final api = ApiService(
      AppConfig(apiBaseUrl: Uri.parse('https://example.test')),
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path == '/users') {
          return http.Response(
            jsonEncode({'id': 1, 'username': 'user_0', 'created_at': 0, 'followerCount': 12}),
            200,
          );
        }
        if (path == '/feed/1') {
          return http.Response(
            jsonEncode({
              'posts': [
                {'id': 9, 'author_id': 2, 'body': 'hello from user_1', 'created_at': 0, 'author_username': 'user_1'},
              ],
              'nextCursor': null,
            }),
            200,
          );
        }
        if (path == '/conversations') {
          return http.Response(
            jsonEncode([
              {
                'id': 5,
                'is_group': false,
                'name': null,
                'other_username': 'user_1',
                'last_message_body': 'see you',
                'last_message_created_at': 0,
                'unread_count': 2,
              },
            ]),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(api),
        socketProvider.overrideWith((ref, userId) => socket),
      ],
      child: const NewsFeedApp(),
    ));
    await tester.pumpAndSettle();

    // Nobody saved: the login screen.
    await tester.enterText(find.byType(TextField), 'user_0');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    // Feed for user_0.
    expect(find.text('@user_0 · 12 followers'), findsOneWidget);
    expect(find.text('hello from user_1'), findsOneWidget);
    expect(socket.controller.hasListener, isTrue);

    // Chat tab.
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(find.text('see you'), findsOneWidget);

    // Back to the feed and log out: login screen again, socket released.
    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(find.text('Log in'), findsOneWidget);
    expect(socket.controller.hasListener, isFalse);
  });
}
