import 'web_push_client.dart';

WebPushClient createWebPushClient() => _Unsupported();

class _Unsupported implements WebPushClient {
  @override
  bool get supported => false;
  @override
  String get permission => 'denied';
  @override
  Future<String> requestPermission() async => 'denied';
  @override
  Future<Map<String, dynamic>> subscribe(String vapidPublicKey) => throw UnsupportedError('web push is web only');
  @override
  Future<void> unsubscribe() async {}
}
