import 'dart:convert';

import 'package:http/http.dart' as http;

import 'oidc_config.dart';
import 'pkce.dart';
import 'token_set.dart';

/// The provider's endpoints, read from its discovery document.
class OidcEndpoints {
  const OidcEndpoints({required this.authorization, required this.token, this.revocation});

  factory OidcEndpoints.fromDiscovery(Map<String, dynamic> json) => OidcEndpoints(
        authorization: Uri.parse(json['authorization_endpoint'] as String),
        token: Uri.parse(json['token_endpoint'] as String),
        revocation: switch (json['revocation_endpoint']) {
          final String url => Uri.parse(url),
          _ => null,
        },
      );

  final Uri authorization;
  final Uri token;
  final Uri? revocation;
}

/// The provider refused (a bad code, a revoked refresh token, ...), or
/// answered something unexpected.
class OidcException implements Exception {
  const OidcException(this.message, {this.error});

  /// The OAuth error code, e.g. `invalid_grant`, when there is one.
  final String? error;
  final String message;

  /// The refresh token no longer works: the user has to sign in again.
  bool get isInvalidGrant => error == 'invalid_grant';

  @override
  String toString() => 'OidcException(${error ?? '-'}): $message';
}

/// The OAuth/OIDC requests themselves, without any state: build the sign-in
/// URL, swap a code for tokens, refresh, revoke.
class OidcClient {
  OidcClient(this.config, {http.Client? httpClient, DateTime Function()? clock})
      : _http = httpClient ?? http.Client(),
        _now = clock ?? DateTime.now;

  final OidcConfig config;
  final http.Client _http;
  final DateTime Function() _now;
  Future<OidcEndpoints>? _endpoints;

  /// Fetched once, then remembered (a failed fetch is retried next time).
  Future<OidcEndpoints> endpoints() => _endpoints ??= _discover().catchError((Object e) {
        _endpoints = null;
        throw e;
      });

  Future<OidcEndpoints> _discover() async {
    final url = config.issuer.replace(path: '${config.issuer.path}/.well-known/openid-configuration');
    final res = await _http.get(url);
    if (res.statusCode != 200) throw OidcException('discovery failed: HTTP ${res.statusCode}');
    return OidcEndpoints.fromDiscovery(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// The page to open in the browser. [state] is echoed back on the redirect,
  /// so the app can tell the answer belongs to this attempt.
  Future<Uri> authorizationUrl({required Pkce pkce, required String state}) async {
    final endpoint = (await endpoints()).authorization;
    return endpoint.replace(queryParameters: {
      ...endpoint.queryParameters,
      'response_type': 'code',
      'client_id': config.clientId,
      'redirect_uri': config.redirectUri.toString(),
      'scope': config.scopes.join(' '),
      'state': state,
      'code_challenge': pkce.challenge,
      'code_challenge_method': pkce.method,
      ...config.extraAuthorizeParameters,
    });
  }

  /// Step 2 of sign-in: the one-time code from the redirect, plus the PKCE
  /// verifier only this app knows, for tokens.
  Future<TokenSet> exchangeCode({required String code, required Pkce pkce}) => _tokenRequest({
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': config.redirectUri.toString(),
        'code_verifier': pkce.verifier,
      });

  /// A new access token, without asking the user again.
  Future<TokenSet> refresh(TokenSet current) {
    final refreshToken = current.refreshToken;
    if (refreshToken == null) throw const OidcException('no refresh token', error: 'invalid_grant');
    return _tokenRequest({'grant_type': 'refresh_token', 'refresh_token': refreshToken}, previous: current);
  }

  /// Tells the provider a token is no longer wanted (on sign-out), so a copy
  /// left behind somewhere stops working. Best effort: false if it failed.
  Future<bool> revoke(String token, {String tokenTypeHint = 'refresh_token'}) async {
    try {
      final endpoint = (await endpoints()).revocation;
      if (endpoint == null) return false;
      final res = await _http.post(endpoint, body: {
        'token': token,
        'token_type_hint': tokenTypeHint,
        'client_id': config.clientId,
      });
      return res.statusCode == 200;
    } on Object {
      return false;
    }
  }

  Future<TokenSet> _tokenRequest(Map<String, String> body, {TokenSet? previous}) async {
    final endpoint = (await endpoints()).token;
    // A public client: it identifies itself with client_id only, no secret.
    final res = await _http.post(endpoint, body: {...body, 'client_id': config.clientId});
    final Object? json;
    try {
      json = jsonDecode(res.body);
    } on FormatException {
      throw OidcException('token endpoint answered HTTP ${res.statusCode} without JSON');
    }
    if (res.statusCode != 200 || json is! Map<String, dynamic>) {
      final map = json is Map ? json : const {};
      throw OidcException(
        map['error_description'] as String? ?? 'token request failed: HTTP ${res.statusCode}',
        error: map['error'] as String?,
      );
    }
    return TokenSet.fromResponse(json, now: _now(), previous: previous);
  }
}
