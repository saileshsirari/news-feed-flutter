import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../data/services/api_service.dart';
import 'push_channel.dart';

/// FCM: Android, and iOS through Firebase (once the Apple account and
/// GoogleService-Info.plist exist). Only usable once Firebase started
/// (see push_setup.dart), i.e. when the app has its Firebase settings.
class FcmChannel implements PushChannel {
  @override
  bool get supported => Firebase.apps.isNotEmpty;

  @override
  Future<bool> get allowed async {
    final status = (await FirebaseMessaging.instance.getNotificationSettings()).authorizationStatus;
    return status == AuthorizationStatus.authorized || status == AuthorizationStatus.provisional;
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  // getToken/deleteToken are deprecated in firebase_messaging 17 in favour
  // of register()/onRegistered, which hand out a Firebase Installation ID
  // that the server sends to differently. The token way still works with
  // the server's FCM v1 "token" target; move over when that's documented.
  @override
  Future<Map<String, dynamic>?> address(ApiService api) async {
    // ignore: deprecated_member_use
    final token = await FirebaseMessaging.instance.getToken();
    return token == null ? null : {'kind': 'fcm', 'token': token};
  }

  @override
  // ignore: deprecated_member_use
  Future<void> stop() => FirebaseMessaging.instance.deleteToken();
}
