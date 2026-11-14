import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/service_providers.dart';
import '../../session/current_user_provider.dart';
import '../event.dart';
import 'save_file_stub.dart' if (dart.library.js_interop) 'save_file_web.dart' as files;

/// Google Calendar's "add this" page for [event]: works on any device,
/// with no sign-in to our server (everything's in the link).
Uri googleCalendarUrl(Event event) {
  String utc(DateTime t) => '${t.toUtc().toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.').first}Z';
  final where = event.isOnline ? (event.onlineUrl ?? 'Online') : [event.placeName, event.address].whereType<String>().join(', ');
  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': event.title,
    'dates': '${utc(event.startsAt)}/${utc(event.endsAt)}',
    'details': [event.description, event.communityName].whereType<String>().join('\n\n'),
    'location': where,
    'ctz': event.timeZone,
  });
}

/// "Add to calendar": Google Calendar, and in a browser, the .ics file too
/// (for Apple Calendar or Outlook).
Future<void> showAddToCalendar(BuildContext context, WidgetRef ref, Event event) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('Google Calendar'),
              onTap: () {
                Navigator.of(sheet).pop();
                launchUrl(googleCalendarUrl(event), mode: LaunchMode.externalApplication);
              },
            ),
            if (files.canSaveFiles)
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Calendar file (.ics)'),
                subtitle: const Text('For Apple Calendar, Outlook and others'),
                onTap: () async {
                  Navigator.of(sheet).pop();
                  await _downloadIcs(context, ref, event);
                },
              ),
          ],
        ),
      ),
    );

Future<void> _downloadIcs(BuildContext context, WidgetRef ref, Event event) async {
  try {
    final config = ref.read(appConfigProvider);
    final userId = ref.read(currentUserProvider).requireValue!.id;
    final uri = Uri.parse('${config.apiBaseUrl}/events/${event.id}/calendar.ics').replace(queryParameters: {'userId': '$userId'});
    final res = await ref.read(apiHttpClientProvider).get(uri);
    if (res.statusCode != 200) throw StateError('status ${res.statusCode}');
    await files.saveFile(res.bodyBytes, 'event-${event.id}.ics', 'text/calendar');
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t get the calendar file.')));
    }
  }
}
