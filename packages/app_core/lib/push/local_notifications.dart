import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// A kind of notification, which people can switch off on its own in
/// Android's settings ("Messages", "Events").
@immutable
class NotificationChannel {
  const NotificationChannel({required this.id, required this.name, required this.description});

  final String id;
  final String name;
  final String description;
}

/// A notification shown on this device: what the inbox lists.
@immutable
class ShownNotification {
  const ShownNotification({required this.title, required this.body, required this.at, this.link});

  final String title;
  final String body;
  final DateTime at;

  /// What tapping it opens (`app://chat/conversation/5?...`), see AppLinks.
  final Uri? link;
}

final _plugin = FlutterLocalNotificationsPlugin();
var _ready = false;
final _taps = StreamController<Uri>.broadcast();
final _shown = StreamController<ShownNotification>.broadcast();

/// Tapped notifications' links, while the app is running.
Stream<Uri> get notificationTaps => _taps.stream;

/// Every notification shown while the app is running (the inbox keeps them).
Stream<ShownNotification> get shownNotifications => _shown.stream;

Future<void> _ensureReady() async {
  if (_ready) return;
  await _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
    onDidReceiveNotificationResponse: (response) {
      final link = linkOfPayload(response.payload);
      if (link != null) _taps.add(link);
    },
  );
  _ready = true;
}

/// The link a notification carries, from its payload.
Uri? linkOfPayload(String? payload) {
  if (payload == null) return null;
  try {
    final link = (jsonDecode(payload) as Map<String, dynamic>)['link'] as String?;
    return link == null ? null : Uri.parse(link);
  } on Object {
    return null;
  }
}

/// The link of the notification that started the app, if one did.
Future<Uri?> launchNotificationLink() async {
  if (kIsWeb) return null;
  try {
    await _ensureReady();
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return linkOfPayload(details!.notificationResponse?.payload);
  } on Object {
    return null; // no plugin on this platform (tests, desktop)
  }
}

/// Shows a notification on Android/iOS. [id] decides which one it replaces
/// (one per chat, say); [link] is what tapping it opens.
Future<void> showLocalNotification({
  required int id,
  required String title,
  required String body,
  required NotificationChannel channel,
  Uri? link,
}) async {
  await _ensureReady();
  await _plugin.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    ),
    payload: jsonEncode({if (link != null) 'link': '$link'}),
  );
  _shown.add(ShownNotification(title: title, body: body, at: DateTime.now(), link: link));
}
