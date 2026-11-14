import 'package:flutter/material.dart';
import 'package:geo_kit/geo_kit.dart';
import 'package:intl/intl.dart';

import 'event.dart';
import 'event_list.dart';
import 'event_screen.dart';

/// One event in a list: a date badge, what and when (on your clock),
/// where, and your RSVP (or that it's full, or cancelled).
class EventTile extends StatelessWidget {
  const EventTile(this.event, {super.key, this.showCommunity = false});

  final Event event;

  /// In a list across communities, say which one it's in.
  final bool showCommunity;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final e = event;
    final status = switch (e) {
      Event(cancelled: true) => ('Cancelled', colors.error),
      Event(myRsvp: RsvpStatus.going) => ('Going', colors.primary),
      Event(myRsvp: RsvpStatus.waitlist, :final myWaitlistPosition) => ('Waitlist #${myWaitlistPosition ?? '?'}', colors.tertiary),
      Event(isFull: true) => ('Full', colors.outline),
      _ => null,
    };
    final where = e.isOnline ? 'Online' : e.placeName ?? '';
    return ListTile(
      leading: _DateBadge(e.localStart, dimmed: e.cancelled || e.past),
      title: Text(
        e.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: e.cancelled ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
      ),
      subtitle: Text(
        [
          DateFormat('HH:mm').format(e.localStart),
          if (e.distanceKm != null) formatDistance(e.distanceKm!),
          if (where.isNotEmpty) where,
          if (showCommunity) e.communityName,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: status == null
          ? null
          : Text(status.$1, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: status.$2)),
      onTap: () => EventScreen.open(context, e.id),
    );
  }
}

/// "16 / NOV", like a calendar page.
class _DateBadge extends StatelessWidget {
  const _DateBadge(this.when, {this.dimmed = false});
  final DateTime when;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Opacity(
      opacity: dimmed ? 0.5 : 1,
      child: Container(
        width: 48,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(8)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${when.day}', style: textTheme.titleMedium?.copyWith(color: colors.onPrimaryContainer)),
            Text(
              DateFormat('MMM').format(when).toUpperCase(),
              style: textTheme.labelSmall?.copyWith(color: colors.onPrimaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}

/// A community's events: upcoming, or past.
class CommunityEventsScreen extends StatelessWidget {
  const CommunityEventsScreen({super.key, required this.communityId, required this.past});

  final int communityId;
  final bool past;

  static Future<void> open(BuildContext context, int communityId, {required bool past}) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => CommunityEventsScreen(communityId: communityId, past: past)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(past ? 'Past events' : 'Upcoming events')),
        body: EventList(key: ValueKey((communityId, past)), communityId: communityId, past: past),
      );
}
