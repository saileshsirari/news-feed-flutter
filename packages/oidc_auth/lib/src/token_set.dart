import 'dart:convert';

/// The tokens one sign-in gives: a short-lived access token for the API, a
/// refresh token to get the next one, and the ID token (who signed in).
class TokenSet {
  const TokenSet({required this.accessToken, required this.expiresAt, this.refreshToken, this.idToken});

  /// From a token endpoint response. A refresh response may leave out the
  /// refresh token (keep the old one) — [previous] supplies it.
  factory TokenSet.fromResponse(Map<String, dynamic> json, {required DateTime now, TokenSet? previous}) {
    final accessToken = json['access_token'];
    if (accessToken is! String) throw const FormatException('token response has no access_token');
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 300;
    return TokenSet(
      accessToken: accessToken,
      expiresAt: now.add(Duration(seconds: expiresIn)),
      refreshToken: json['refresh_token'] as String? ?? previous?.refreshToken,
      idToken: json['id_token'] as String? ?? previous?.idToken,
    );
  }

  final String accessToken;
  final DateTime expiresAt;
  final String? refreshToken;
  final String? idToken;

  /// Time to refresh: a token about to expire might expire mid-request.
  bool needsRefresh(DateTime now, {Duration margin = const Duration(seconds: 60)}) =>
      !now.add(margin).isBefore(expiresAt);

  String encode() => jsonEncode({
        'access_token': accessToken,
        'expires_at': expiresAt.toUtc().toIso8601String(),
        'refresh_token': ?refreshToken,
        'id_token': ?idToken,
      });

  static TokenSet decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return TokenSet(
      accessToken: json['access_token'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      refreshToken: json['refresh_token'] as String?,
      idToken: json['id_token'] as String?,
    );
  }
}
