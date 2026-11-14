import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:oidc_auth/oidc_auth.dart';

import '../config/app_config.dart';
import '../data/services/api_service.dart';
import '../events/event.dart';
import '../events/events_api.dart';

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
    // With the app open, chat arrives over the socket; event notices still
    // need showing.
    FirebaseMessaging.onMessage.listen((push) {
      if (push.data['type'] == 'event') showEventPush(push.data);
    });
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
  if (data['type'] == 'event') return showEventPush(data);
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
      // End-to-end encrypted: the server's copy has no text. (Decrypting
      // here, in the background, comes later.)
      body = message['mode'] == 'e2e'
          ? '🔒 New message'
          : text.isNotEmpty
              ? text
              : '📷 Photo or video';
    }
  } on Object catch (e) {
    debugPrint('[push] couldn\'t fetch the message, showing a plain notification: $e');
  }
  await showChatNotification(conversationId: conversationId, title: title, body: body);
}

/// An event notice: the push says only which event and why; the words come
/// from the event itself, fetched with the saved sign-in (so Google never
/// sees what or where it is), with times on this phone's clock.
Future<void> showEventPush(Map<String, dynamic> data) async {
  final eventId = int.tryParse('${data['eventId']}');
  if (eventId == null) return;
  final reason = '${data['reason']}';
  var title = 'News Feed';
  var body = 'An event you follow has an update';
  try {
    final event = await _fetchEvent(eventId);
    if (event != null) (title, body) = eventNotice(event, reason);
  } on Object catch (e) {
    debugPrint('[push] couldn\'t fetch the event, showing a plain notification: $e');
  }
  await _show(
    // Its own number range, so an event never replaces a chat's notification.
    id: 1000000000 + eventId % 1000000000,
    title: title,
    body: body,
    channel: _eventsChannel,
    payload: {'eventId': eventId},
  );
}

/// What a notice about [event] says, for each [reason] the server sends.
(String, String) eventNotice(Event event, String reason) {
  final where = event.isOnline ? 'Online' : event.placeName ?? 'In person';
  final when = '${event.localWhen} · $where';
  return switch (reason) {
    'new' => ('New event in ${event.communityName}', '${event.title} · $when'),
    'changed' => ('Changed: ${event.title}', 'Now $when'),
    'cancelled' => ('Cancelled: ${event.title}', 'It was planned for ${event.localWhen}.'),
    'promoted' => ('You\'re in: ${event.title}', 'A spot opened up. $when'),
    'reminder_1h' => ('Starting soon: ${event.title}', when),
    'reminder_24h' => ('Coming up: ${event.title}', when),
    _ => (event.title, when),
  };
}

Future<Event?> _fetchEvent(int eventId) async {
  final config = AppConfig.fromEnvironment();
  final oidc = config.oidc;
  if (oidc == null) return null;
  final auth = AuthSession(client: OidcClient(oidc), store: SecureTokenStore());
  if (!await auth.isSignedIn) return null;
  // userId is only read under development login; a real sign-in carries its own.
  return EventsApi(config, AuthorizedClient(auth.accessToken), userId: 0).get(eventId);
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

const _eventsChannel = AndroidNotificationDetails(
  'events',
  'Events',
  channelDescription: 'New events, changes and reminders',
  importance: Importance.high,
  priority: Priority.high,
);

/// One notification per chat: a newer message replaces the older one.
Future<void> showChatNotification({required int conversationId, required String title, required String body}) =>
    _show(id: conversationId, title: title, body: body, channel: _channel, payload: {'conversationId': conversationId});

Future<void> _show({
  required int id,
  required String title,
  required String body,
  required AndroidNotificationDetails channel,
  required Map<String, Object?> payload,
}) async {
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
    id: id,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(android: channel, iOS: const DarwinNotificationDetails()),
    payload: jsonEncode(payload),
  );
}
