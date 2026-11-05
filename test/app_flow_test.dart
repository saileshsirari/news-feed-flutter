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
import 'package:news_feed_flutter/session/device_registration.dart';
import 'package:oidc_auth/oidc_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_chat_server.dart';
import 'helpers/fake_socket.dart';

/// The whole app against a fake server: every screen and notifier builds
/// for real, so a mistake that only shows up when widgets mount (not in a
/// notifier test on its own) fails here.
/// A fake server: the user (for a test-account login or /me), their feed,
/// their chats.
Future<http.Response> fakeServer(http.Request request) async {
  final path = request.url.path;
  if (path == '/users' || path == '/me') {
    return http.Response(jsonEncode({'id': 1, 'username': 'user_0', 'created_at': 0, 'followerCount': 12}), 200);
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
}

void main() {
  testWidgets('log in, see the feed, open chats, log out', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final socket = FakeSocket();
    final api = ApiService(
      AppConfig(apiBaseUrl: Uri.parse('https://example.test')),
      httpClient: MockClient(fakeServer),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiServiceProvider.overrideWithValue(api),
          socketProvider.overrideWith((ref, userId) => socket),
          ...localChatOverrides(),
        ],
        child: const NewsFeedApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Nobody saved: the login screen.
    await tester.enterText(find.byType(TextField), 'user_0');
    await tester.tap(find.text('Log in as test account'));
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
    expect(find.text('Log in as test account'), findsOneWidget);
    expect(socket.controller.hasListener, isFalse);
  });

  testWidgets('sign in through the provider, the API gets the token, sign out revokes it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final socket = FakeSocket();
    final providerCalls = <String>[];
    final provider = MockClient((request) async {
      providerCalls.add(request.url.path);
      return switch (request.url.path) {
        '/.well-known/openid-configuration' => http.Response(
          jsonEncode({
            'authorization_endpoint': 'https://issuer.test/authorize',
            'token_endpoint': 'https://issuer.test/token',
            'revocation_endpoint': 'https://issuer.test/revoke',
          }),
          200,
        ),
        '/token' => http.Response(
          jsonEncode({'access_token': 'token-1', 'refresh_token': 'refresh-1', 'expires_in': 3600}),
          200,
        ),
        _ => http.Response('', 200),
      };
    });
    final auth = AuthSession(
      client: OidcClient(
        OidcConfig(
          issuer: Uri.parse('https://issuer.test'),
          clientId: 'app',
          redirectUri: Uri.parse('com.example:/callback'),
        ),
        httpClient: provider,
      ),
      store: MemoryTokenStore(),
      // The user signs in on the provider's page and is sent back.
      browser: (url, redirectUri) async =>
          redirectUri.replace(queryParameters: {'code': 'c', 'state': url.queryParameters['state']!}),
    );
    final apiAuthorization = <String?>[];
    final deviceRegistrations = <String>[];
    final api = ApiService(
      AppConfig(apiBaseUrl: Uri.parse('https://example.test')),
      httpClient: AuthorizedClient(
        auth.accessToken,
        MockClient((request) async {
          apiAuthorization.add(request.headers['Authorization']);
          if (request.method == 'PUT' && request.url.path.startsWith('/devices/')) {
            deviceRegistrations.add('${request.url.pathSegments.last} ${request.body}');
            return http.Response('{}', 201);
          }
          return fakeServer(request);
        }),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(auth),
          apiServiceProvider.overrideWithValue(api),
          socketProvider.overrideWith((ref, userId) => socket),
          deviceDescriptionProvider.overrideWithValue(() async => (name: 'Test phone', platform: 'android')),
          ...localChatOverrides(),
        ],
        child: const NewsFeedApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sign-in')));
    await tester.pumpAndSettle();

    // The server said who we are (GET /me), and every request carried the token.
    expect(find.text('@user_0 · 12 followers'), findsOneWidget);
    expect(apiAuthorization, isNotEmpty);
    expect(apiAuthorization.toSet(), {'Bearer token-1'});
    // This install registered itself, once, with a stable random id (in the
    // background, so give it a moment).
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(deviceRegistrations, hasLength(1));
    expect(deviceRegistrations.single, matches(RegExp(r'^[a-z0-9]{32} \{"name":"Test phone","platform":"android"\}$')));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sign-in')), findsOneWidget);
    expect(providerCalls, contains('/revoke'));
    expect(await auth.isSignedIn, isFalse);
  });
}
