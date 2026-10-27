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
class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  factory AppConfig.fromEnvironment() => AppConfig(
        apiBaseUrl: Uri.parse(
          const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'https://150-230-234-113.sslip.io',
          ),
        ),
      );

  final Uri apiBaseUrl;

  /// The realtime socket lives on the same host. ws/wss must follow
  /// http/https: behind Caddy's TLS termination a plain ws:// fails.
  Uri webSocketUri({required int userId}) => apiBaseUrl.replace(
        scheme: apiBaseUrl.scheme == 'https' ? 'wss' : 'ws',
        path: '/ws',
        queryParameters: {'userId': '$userId'},
      );
}
