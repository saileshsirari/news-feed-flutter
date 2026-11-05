/// One app registered with the provider.
///
/// Zitadel gives each platform its own app (a "native" one with a custom
/// scheme redirect, a "web" one with an http(s) redirect), so the caller
/// picks the right one for the platform it runs on.
class OidcConfig {
  const OidcConfig({
    required this.issuer,
    required this.clientId,
    required this.redirectUri,
    this.scopes = const ['openid', 'profile', 'email', 'offline_access'],
    this.extraAuthorizeParameters = const {},
  });

  /// e.g. https://my-instance.zitadel.cloud — the discovery document lives
  /// at issuer + /.well-known/openid-configuration.
  final Uri issuer;
  final String clientId;

  /// Where the provider sends the browser back: `com.example.app:/callback`
  /// on a phone, `http://localhost:8766/redirect.html` on the web.
  final Uri redirectUri;

  /// `offline_access` asks for a refresh token, so a sign-in lasts longer
  /// than one access token (minutes to hours).
  final List<String> scopes;

  /// Anything provider-specific, e.g. `prompt: select_account`.
  final Map<String, String> extraAuthorizeParameters;
}
