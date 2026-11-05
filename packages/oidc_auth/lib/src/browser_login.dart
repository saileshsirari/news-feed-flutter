import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

/// Shows the provider's sign-in page and returns the URL it redirected back
/// to (carrying `code` and `state`). Throws if the user closes it.
///
/// A function, so tests can stand in for the browser.
typedef BrowserLogin = Future<Uri> Function(Uri authorizeUrl, Uri redirectUri);

/// The system browser: Custom Tabs on Android, ASWebAuthenticationSession on
/// iOS/macOS, a popup on the web (which needs a page at the redirect URL
/// that hands the URL back; see the app's web/ folder).
///
/// A system browser rather than a WebView inside the app, so the app never
/// sees the password, and the user can check the address bar.
Future<Uri> systemBrowserLogin(Uri authorizeUrl, Uri redirectUri) async {
  final result = await FlutterWebAuth2.authenticate(
    url: authorizeUrl.toString(),
    callbackUrlScheme: redirectUri.scheme,
  );
  return Uri.parse(result);
}
