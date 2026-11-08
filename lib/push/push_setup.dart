import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:oidc_auth/oidc_auth.dart';

import '../config/app_config.dart';
import '../data/services/api_service.dart';

/// Starts Firebase on Android and iOS, so FcmChannel can work, and hooks up
/// what happens when a push arrives with the app in the background or
/// closed. Without Firebase settings for this platform (e.g. iOS before the
/// Apple account), push is simply off; nothing else is affected.
Future<void> setUpPush() async {
  if (kIsWeb || !(defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
    return;
  }
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(handlePushInBackground);
  } on Object catch (e) {
    debugPrint('[push] Firebase not set up for this platform: $e');
  }
}

/// A push while the app is in the background or closed. It carries only ids
/// (Google never sees the text): fetch the message from our server with the
/// saved sign-in, and show it. Runs in its own isolate, so it builds what it
/// needs itself rather than using the app's providers.
@pragma('vm:entry-point')
Future<void> handlePushInBackground(RemoteMessage push) async {
  await Firebase.initializeApp();
  final data = push.data;
  if (data['type'] != 'message') return;
  final conversationId = int.tryParse('${data['conversationId']}');
  final seq = int.tryParse('${data['seq']}');
  if (conversationId == null || seq == null) return;

  var title = 'News Feed';
  var body = 'New message';
  try {
    final message = await _fetchMessage(conversationId, seq);
    if (message != null) {
      title = '@${message['sender_username']}';
      final text = (message['body'] as String? ?? '').trim();
      body = text.isNotEmpty ? text : '📷 Photo or video';
    }
  } on Object catch (e) {
    debugPrint('[push] couldn\'t fetch the message, showing a plain notification: $e');
  }
  await showChatNotification(conversationId: conversationId, title: title, body: body);
}

/// The message with [seq], from our server, signed in as the saved user.
Future<Map<String, dynamic>?> _fetchMessage(int conversationId, int seq) async {
  final config = AppConfig.fromEnvironment();
  final oidc = config.oidc;
  if (oidc == null) return null;
  final auth = AuthSession(client: OidcClient(oidc), store: SecureTokenStore());
  if (!await auth.isSignedIn) return null;
  final api = ApiService(config, httpClient: AuthorizedClient(auth.accessToken));
  final page = await api.getMessagesBySeq(conversationId, null, afterSeq: seq - 1, limit: 1);
  return page.messages.isEmpty ? null : page.messages.first;
}

final _notifications = FlutterLocalNotificationsPlugin();
var _notificationsReady = false;

const _channel = AndroidNotificationDetails(
  'messages',
  'Messages',
  channelDescription: 'New chat messages',
  importance: Importance.high,
  priority: Priority.high,
);

/// One notification per chat: a newer message replaces the older one.
Future<void> showChatNotification({required int conversationId, required String title, required String body}) async {
  if (!_notificationsReady) {
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    _notificationsReady = true;
  }
  await _notifications.show(
    id: conversationId,
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(android: _channel, iOS: DarwinNotificationDetails()),
    payload: jsonEncode({'conversationId': conversationId}),
  );
}
