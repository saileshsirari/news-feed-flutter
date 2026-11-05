import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oidc_auth/oidc_auth.dart';

final issuer = Uri.parse('https://issuer.test');
final redirect = Uri.parse('com.example.app:/callback');
final config = OidcConfig(
  issuer: issuer,
  clientId: 'client-1',
  redirectUri: redirect,
  extraAuthorizeParameters: const {'prompt': 'select_account'},
);

/// A pretend provider: discovery, token and revocation endpoints.
class FakeProvider {
  final requests = <http.Request>[];
  int tokenCounter = 0;
  bool refreshRevoked = false;

  late final client = MockClient((request) async {
    requests.add(request);
    switch (request.url.path) {
      case '/.well-known/openid-configuration':
        return http.Response(
          jsonEncode({
            'authorization_endpoint': 'https://issuer.test/oauth/v2/authorize',
            'token_endpoint': 'https://issuer.test/oauth/v2/token',
            'revocation_endpoint': 'https://issuer.test/oauth/v2/revoke',
          }),
          200,
        );
      case '/oauth/v2/token':
        final form = request.bodyFields;
        if (form['grant_type'] == 'refresh_token' && refreshRevoked) {
          return http.Response(jsonEncode({'error': 'invalid_grant', 'error_description': 'revoked'}), 400);
        }
        if (form['grant_type'] == 'authorization_code' && form['code'] != 'good-code') {
          return http.Response(jsonEncode({'error': 'invalid_grant'}), 400);
        }
        tokenCounter++;
        return http.Response(
          jsonEncode({
            'access_token': 'access-$tokenCounter',
            'expires_in': 3600,
            // A refresh answer leaves the refresh token out: keep the old one.
            if (form['grant_type'] == 'authorization_code') 'refresh_token': 'refresh-1',
          }),
          200,
        );
      case '/oauth/v2/revoke':
        return http.Response('', 200);
    }
    return http.Response('not found', 404);
  });

  Iterable<http.Request> to(String path) => requests.where((r) => r.url.path == path);
}

void main() {
  test('PKCE challenge matches the RFC 7636 example', () {
    final pkce = Pkce.fromVerifier('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk');
    expect(pkce.challenge, 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    expect(Pkce.generate().verifier, hasLength(64));
  });

  test('the sign-in URL carries the client, redirect, PKCE challenge and state', () async {
    final provider = FakeProvider();
    final client = OidcClient(config, httpClient: provider.client);
    final url = await client.authorizationUrl(pkce: Pkce.fromVerifier('v' * 50), state: 's1');
    expect(url.path, '/oauth/v2/authorize');
    expect(url.queryParameters, {
      'response_type': 'code',
      'client_id': 'client-1',
      'redirect_uri': 'com.example.app:/callback',
      'scope': 'openid profile email offline_access',
      'state': 's1',
      'code_challenge': Pkce.fromVerifier('v' * 50).challenge,
      'code_challenge_method': 'S256',
      'prompt': 'select_account',
    });
    // Discovery is fetched once.
    await client.authorizationUrl(pkce: Pkce.generate(), state: 's2');
    expect(provider.to('/.well-known/openid-configuration'), hasLength(1));
  });

  group('AuthSession', () {
    late FakeProvider provider;
    late MemoryTokenStore store;
    late DateTime now;

    AuthSession session({String code = 'good-code', bool echoState = true, String? error}) {
      return AuthSession(
        client: OidcClient(config, httpClient: provider.client, clock: () => now),
        store: store,
        clock: () => now,
        // Plays the browser: the user signs in and is sent back.
        browser: (url, redirectUri) async => redirectUri.replace(queryParameters: {
          if (error != null) 'error': error else 'code': code,
          if (echoState) 'state': url.queryParameters['state']!,
        }),
      );
    }

    setUp(() {
      provider = FakeProvider();
      store = MemoryTokenStore();
      now = DateTime.utc(2026, 11, 5, 12);
    });

    test('signs in: swaps the code and its PKCE verifier for tokens, and keeps them', () async {
      final auth = session();
      expect(await auth.isSignedIn, isFalse);
      expect(await auth.accessToken(), isNull);

      await auth.signIn();

      expect(await auth.accessToken(), 'access-1');
      expect(store.tokens?.refreshToken, 'refresh-1');
      final exchange = provider.to('/oauth/v2/token').single.bodyFields;
      expect(exchange['grant_type'], 'authorization_code');
      expect(exchange['code_verifier'], hasLength(64));
      expect(exchange['client_id'], 'client-1');
    });

    test('refuses a redirect for another attempt (state mismatch) or an error', () async {
      await expectLater(session(echoState: false).signIn(), throwsA(isA<SignInCancelledException>()));
      await expectLater(session(error: 'access_denied').signIn(), throwsA(isA<SignInCancelledException>()));
      expect(provider.to('/oauth/v2/token'), isEmpty);
      expect(store.tokens, isNull);
    });

    test('refreshes an expiring token once, even when asked many times at once', () async {
      final auth = session();
      await auth.signIn();
      now = now.add(const Duration(minutes: 59, seconds: 30)); // within the 60 s margin

      final tokens = await Future.wait(List.generate(5, (_) => auth.accessToken()));

      expect(tokens.toSet(), {'access-2'});
      expect(provider.to('/oauth/v2/token').where((r) => r.bodyFields['grant_type'] == 'refresh_token'), hasLength(1));
      expect(store.tokens?.refreshToken, 'refresh-1'); // kept from before
    });

    test('a revoked refresh token signs the user out', () async {
      final auth = session();
      await auth.signIn();
      provider.refreshRevoked = true;
      now = now.add(const Duration(hours: 2));

      expect(await auth.accessToken(), isNull);
      expect(store.tokens, isNull);
    });

    test('a saved sign-in survives a restart', () async {
      await session().signIn();
      expect(await session().accessToken(), 'access-1');
    });

    test('sign-out forgets the tokens and revokes the refresh token', () async {
      final auth = session();
      await auth.signIn();
      await auth.signOut();

      expect(store.tokens, isNull);
      expect(await auth.accessToken(), isNull);
      expect(provider.to('/oauth/v2/revoke').single.bodyFields, {
        'token': 'refresh-1',
        'token_type_hint': 'refresh_token',
        'client_id': 'client-1',
      });
    });
  });

  test('tokens survive being saved and read back', () {
    final tokens = TokenSet(accessToken: 'a', expiresAt: DateTime.utc(2026), refreshToken: 'r');
    final back = TokenSet.decode(tokens.encode());
    expect([back.accessToken, back.expiresAt, back.refreshToken, back.idToken], ['a', DateTime.utc(2026), 'r', null]);
  });

  test('AuthorizedClient adds the bearer token only when there is one', () async {
    final seen = <String?>[];
    final inner = MockClient((r) async {
      seen.add(r.headers['Authorization']);
      return http.Response('ok', 200);
    });
    String? token = 'abc';
    final client = AuthorizedClient(() async => token, inner);
    await client.get(Uri.parse('https://api.test/me'));
    token = null;
    await client.get(Uri.parse('https://api.test/me'));
    expect(seen, ['Bearer abc', null]);
  });
}
