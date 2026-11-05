import 'dart:convert';

import 'package:chat_store/chat_store.dart';
import 'package:chat_store/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/chat/local/local_chat.dart';
import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/api_service.dart';
import 'package:news_feed_flutter/data/services/service_providers.dart';
import 'package:news_feed_flutter/data/services/socket_provider.dart';
import 'package:news_feed_flutter/session/current_user_provider.dart';
import 'package:oidc_auth/oidc_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Nothing listens on this port, so the socket's connect attempt fails
  // instantly and harmlessly; these tests only care about its lifecycle.
  final config = AppConfig(apiBaseUrl: Uri.parse('http://127.0.0.1:9'));

  /// A container whose ApiService answers GET /users?username=... with [user]
  /// (or 404 when null) instead of hitting the network.
  ProviderContainer containerReturning(Map<String, dynamic>? user) {
    final api = ApiService(
      config,
      httpClient: MockClient(
        (request) async => user == null ? http.Response('not found', 404) : http.Response(jsonEncode(user), 200),
      ),
    );
    return ProviderContainer.test(
      overrides: [appConfigProvider.overrideWithValue(config), apiServiceProvider.overrideWithValue(api)],
    );
  }

  const celebrity = {'id': 7, 'username': 'celebrity', 'created_at': 0, 'followerCount': 1000};

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts logged out when nothing is saved', () async {
    final container = containerReturning(celebrity);

    expect(await container.read(currentUserProvider.future), isNull);
  });

  test('login sets the user and saves the session for the next app start', () async {
    final container = containerReturning(celebrity);
    await container.read(currentUserProvider.future);

    await container.read(currentUserProvider.notifier).login('celebrity');

    final user = container.read(currentUserProvider).value!;
    expect((user.id, user.username, user.followerCount), (7, 'celebrity', 1000));

    // A fresh container is a fresh app start: it reads the saved session.
    final restarted = containerReturning(celebrity);
    expect((await restarted.read(currentUserProvider.future))?.id, 7);
  });

  test('a failed login throws and stays logged out', () async {
    final container = containerReturning(null);
    await container.read(currentUserProvider.future);

    await expectLater(container.read(currentUserProvider.notifier).login('nobody'), throwsA(anything));

    expect(container.read(currentUserProvider).value, isNull);
  });

  test('logout clears the user and the saved session', () async {
    final container = containerReturning(celebrity);
    await container.read(currentUserProvider.future);
    await container.read(currentUserProvider.notifier).login('celebrity');

    await container.read(currentUserProvider.notifier).logout();

    expect(container.read(currentUserProvider).value, isNull);
    expect(await containerReturning(celebrity).read(currentUserProvider.future), isNull);
  });

  test('logout works with chat history on the device, and deletes it', () async {
    final api = ApiService(config, httpClient: MockClient((request) async => http.Response(jsonEncode(celebrity), 200)));
    // One in-memory database we keep a handle on, to look inside afterwards.
    final db = inMemoryChatDatabase();
    addTearDown(db.close);
    final container = ProviderContainer.test(overrides: [
      appConfigProvider.overrideWithValue(config),
      apiServiceProvider.overrideWithValue(api),
      chatDatabaseProvider.overrideWith((ref, userId) => db),
    ]);
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

  test('every listener of a user gets the same socket, until nobody listens', () async {
    final container = containerReturning(celebrity);

    final a = container.listen(socketProvider(7), (_, _) {});
    final b = container.listen(socketProvider(7), (_, _) {});
    expect(a.read(), same(b.read()));
    expect(a.read().userId, 7);

    final first = a.read();
    a.close();
    b.close();
    await container.pump(); // let autoDispose run

    // Disposed (and disconnected) once the last listener left, so the next
    // listener gets a brand-new connection.
    final c = container.listen(socketProvider(7), (_, _) {});
    expect(c.read(), isNot(same(first)));
  });

  group('with a saved sign-in', () {
    /// An AuthSession that already holds tokens (as after an earlier sign-in).
    AuthSession signedIn(MemoryTokenStore store, List<String> providerCalls) => AuthSession(
      client: OidcClient(
        OidcConfig(issuer: Uri.parse('https://issuer.test'), clientId: 'app', redirectUri: Uri.parse('x:/cb')),
        httpClient: MockClient((request) async {
          providerCalls.add(request.url.path);
          return request.url.path == '/.well-known/openid-configuration'
              ? http.Response(
                  jsonEncode({
                    'authorization_endpoint': 'https://issuer.test/a',
                    'token_endpoint': 'https://issuer.test/t',
                    'revocation_endpoint': 'https://issuer.test/r',
                  }),
                  200,
                )
              : http.Response('', 200);
        }),
      ),
      store: store,
    );

    ProviderContainer containerWith(AuthSession auth, http.Response Function(http.Request) server) =>
        ProviderContainer.test(
          overrides: [
            appConfigProvider.overrideWithValue(config),
            authSessionProvider.overrideWithValue(auth),
            apiServiceProvider.overrideWithValue(
              ApiService(config, httpClient: AuthorizedClient(auth.accessToken, MockClient((r) async => server(r)))),
            ),
          ],
        );

    TokenSet saved() => TokenSet(
      accessToken: 'token-1',
      refreshToken: 'refresh-1',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );

    test('starts as the user the server says the token belongs to', () async {
      final container = containerWith(signedIn(MemoryTokenStore(saved()), []), (r) {
        expect(r.url.path, '/me');
        expect(r.headers['Authorization'], 'Bearer token-1');
        return http.Response(jsonEncode(celebrity), 200);
      });

      expect((await container.read(currentUserProvider.future))?.username, 'celebrity');
    });

    test('a sign-in the server rejects is dropped: logged out, tokens gone', () async {
      final store = MemoryTokenStore(saved());
      final calls = <String>[];
      final container = containerWith(signedIn(store, calls), (_) => http.Response('{"error":"invalid token"}', 401));

      expect(await container.read(currentUserProvider.future), isNull);
      expect(store.tokens, isNull);
      expect(calls, contains('/r')); // and the refresh token revoked
    });
  });
}
