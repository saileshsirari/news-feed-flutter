import 'package:flutter/foundation.dart';
import 'package:oidc_auth/oidc_auth.dart';

/// Where the app talks to. The one place the server address lives.
///
/// The default points at the deployed VM (public host behind Caddy's TLS),
/// which works from any network. Override it at build time instead of
/// editing code, e.g. to use the backend running on your Mac:
///
///     flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000        # Android emulator
///     flutter run --dart-define=API_BASE_URL=http://192.168.1.20:3000    # real phone on your LAN
///
/// (10.0.2.2 is the emulator's alias for the host's localhost and does not
/// exist on real hardware; find your Mac's LAN IP with `ipconfig getifaddr en0`.)
///
/// Sign-in goes through Zitadel (see [_zitadel]); the same --dart-define
/// trick points it at another instance, or `OIDC_ISSUER=` (empty) turns it
/// off, leaving only the test-account login.
class AppConfig {
  const AppConfig({required this.apiBaseUrl, this.oidc});

  factory AppConfig.fromEnvironment() => AppConfig(
        apiBaseUrl: Uri.parse(
          const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'https://150-230-234-113.sslip.io',
          ),
        ),
        oidc: _zitadel(),
      );

  final Uri apiBaseUrl;

  /// Null when sign-in isn't set up (and in tests): test accounts only.
  final OidcConfig? oidc;

  /// Zitadel registers each platform as its own app: a "native" one that
  /// redirects to a custom scheme the phone routes back to this app, and a
  /// "web" one that redirects to a page on the site itself
  /// (web/redirect.html). Both belong to one project, whose id the server
  /// checks as the token's audience.
  static OidcConfig? _zitadel() {
    const issuer = String.fromEnvironment(
      'OIDC_ISSUER',
      defaultValue: 'https://beautiful-apps-instance-fyg6ba.us1.zitadel.cloud',
    );
    if (issuer.isEmpty) return null;
    const projectId = String.fromEnvironment('OIDC_PROJECT_ID', defaultValue: '398222501844392882');
    return OidcConfig(
      issuer: Uri.parse(issuer),
      clientId: kIsWeb
          ? const String.fromEnvironment('OIDC_WEB_CLIENT_ID', defaultValue: '398223186254207922')
          : const String.fromEnvironment('OIDC_NATIVE_CLIENT_ID', defaultValue: '398222645574802354'),
      // On the web: wherever the app is served from, e.g.
      // http://localhost:8766/redirect.html (which must be registered).
      redirectUri: kIsWeb ? Uri.base.resolve('/redirect.html') : Uri.parse('com.newsfeed.newsfeedflutter:/callback'),
      scopes: const [
        'openid',
        'profile',
        'email',
        'offline_access',
        // Puts the project id in the access token's audience.
        'urn:zitadel:iam:org:project:id:$projectId:aud',
      ],
      // Always show the account picker, so signing out and in again can
      // switch accounts instead of silently reusing the last one.
      extraAuthorizeParameters: const {'prompt': 'select_account'},
    );
  }

  /// The realtime socket lives on the same host. ws/wss must follow
  /// http/https: behind Caddy's TLS termination a plain ws:// fails.
  Uri webSocketUri({required int userId}) => apiBaseUrl.replace(
        scheme: apiBaseUrl.scheme == 'https' ? 'wss' : 'ws',
        path: '/ws',
        queryParameters: {'userId': '$userId'},
      );
}
