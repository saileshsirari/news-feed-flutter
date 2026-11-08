import '../data/services/api_service.dart';
import 'web_push_client.dart';

/// How this platform receives pushes: Web Push in a browser, FCM on
/// Android (and iOS through Firebase). PushRegistration only talks to this.
abstract interface class PushChannel {
  /// Whether this platform can receive pushes at all.
  bool get supported;

  /// Notifications are allowed (the user said yes to the system prompt).
  Future<bool> get allowed;

  /// Shows the system's "Allow notifications?" prompt; true if allowed.
  Future<bool> requestPermission();

  /// Where the server should send this device's pushes, as the server's
  /// PUT /push/endpoints/:deviceId expects it; null if the server can't
  /// send this kind (not set up there).
  Future<Map<String, dynamic>?> address(ApiService api);

  /// Stop receiving (notifications turned off).
  Future<void> stop();
}

/// Web Push: the browser subscribes with our server's public VAPID key.
class WebPushChannel implements PushChannel {
  WebPushChannel(this._client);

  final WebPushClient _client;

  @override
  bool get supported => _client.supported;

  @override
  Future<bool> get allowed async => _client.permission == 'granted';

  @override
  Future<bool> requestPermission() async => await _client.requestPermission() == 'granted';

  @override
  Future<Map<String, dynamic>?> address(ApiService api) async {
    final key = await api.getWebPushKey();
    if (key == null) return null;
    return {'kind': 'webpush', 'subscription': await _client.subscribe(key)};
  }

  @override
  Future<void> stop() => _client.unsubscribe();
}
