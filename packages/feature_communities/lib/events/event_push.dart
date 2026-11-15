import 'package:app_core/app_core.dart';
import 'package:flutter/foundation.dart';

import 'event.dart';
import 'events_api.dart';

const _events = NotificationChannel(id: 'events', name: 'Events', description: 'New events, changes and reminders');

/// An event notice: the push says only which event and why; the words come
/// from the event itself, fetched with the saved sign-in (so Google never
/// sees what or where it is), with times on this phone's clock.
Future<void> showEventPush(Map<String, dynamic> data) async {
  final eventId = int.tryParse('${data['eventId']}');
  if (eventId == null) return;
  final reason = '${data['reason']}';
  var title = 'Event update';
  var body = 'An event you follow has an update';
  try {
    final event = await _fetchEvent(eventId);
    if (event != null) (title, body) = eventNotice(event, reason);
  } on Object catch (e) {
    debugPrint('[push] couldn\'t fetch the event, showing a plain notification: $e');
  }
  await showLocalNotification(
    // Its own number range, so an event never replaces a chat's notification.
    id: 1000000000 + eventId % 1000000000,
    title: title,
    body: body,
    channel: _events,
    link: AppLinks.event(eventId),
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
  final signIn = await savedSignIn();
  if (signIn == null) return null;
  // userId is only read under development login; a real sign-in carries its own.
  return EventsApi(signIn.config, signIn.client, userId: 0).get(eventId);
}
