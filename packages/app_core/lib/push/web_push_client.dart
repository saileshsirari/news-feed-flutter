import 'web_push_stub.dart' if (dart.library.js_interop) 'web_push_web.dart' as impl;

/// The browser's side of Web Push: asking permission, and subscribing this
/// browser to pushes signed with our server's key. Only does anything on
/// the web; elsewhere [supported] is false.
abstract interface class WebPushClient {
  bool get supported;

  /// "granted", "denied" or "default" (not asked yet).
  String get permission;

  /// Shows the browser's "Allow notifications?" prompt. Browsers only allow
  /// it right after a click, so call it from a button.
  Future<String> requestPermission();

  /// This browser's subscription ({endpoint, keys: {p256dh, auth}}), made if
  /// needed, for pushes signed with [vapidPublicKey].
  Future<Map<String, dynamic>> subscribe(String vapidPublicKey);

  Future<void> unsubscribe();
}

WebPushClient createWebPushClient() => impl.createWebPushClient();
