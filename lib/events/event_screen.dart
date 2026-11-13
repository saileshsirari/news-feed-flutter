import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_media/shared_media.dart';
import 'package:url_launcher/url_launcher.dart';

import '../communities/community_screen.dart';
import '../data/services/api_service.dart';
import '../profile/profile_screen.dart';
import '../profile/user_avatar.dart';
import 'edit_event_screen.dart';
import 'event.dart';
import 'events_providers.dart';

/// One event: when (on your clock, and the event's if they differ), where,
/// how many are going, and your RSVP. Organisers can edit or cancel it.
class EventScreen extends ConsumerWidget {
  const EventScreen({super.key, required this.eventId});

  final int eventId;

  static Future<void> open(BuildContext context, int eventId) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventScreen(eventId: eventId)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(eventProvider(eventId));
    return Scaffold(
      appBar: AppBar(
        title: Text(event.value?.title ?? 'Event'),
        actions: [
          if (event.value case final e? when e.canManage && !e.cancelled && !e.past)
            PopupMenuButton<String>(
              onSelected: (action) => action == 'edit' ? EditEventScreen.edit(context, e) : _confirmCancel(context, ref, e),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'))),
                PopupMenuItem(
                  value: 'cancel',
                  child: ListTile(leading: Icon(Icons.event_busy_outlined), title: Text('Cancel event')),
                ),
              ],
            ),
        ],
      ),
      body: switch (event) {
        AsyncData(:final value) => RefreshIndicator(
            onRefresh: () => ref.refresh(eventProvider(eventId).future),
            child: ListView(children: [_Details(value), _Attendees(value)]),
          ),
        AsyncError() => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Couldn\'t load this event.'),
                TextButton(onPressed: () => ref.invalidate(eventProvider(eventId)), child: const Text('Try again')),
              ],
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref, Event event) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Cancel ${event.title}?'),
        content: const Text('It stays listed as cancelled, and nobody can RSVP any more.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('Cancel event')),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await ref.read(eventProvider(event.id).notifier).cancel();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t cancel it. Try again.')));
      }
    }
  }
}

class _Details extends ConsumerStatefulWidget {
  const _Details(this.event);
  final Event event;

  @override
  ConsumerState<_Details> createState() => _DetailsState();
}

class _DetailsState extends ConsumerState<_Details> {
  bool _busy = false;

  Future<void> _rsvp(bool going) async {
    setState(() => _busy = true);
    final notifier = ref.read(eventProvider(widget.event.id).notifier);
    try {
      await (going ? notifier.rsvp() : notifier.unrsvp());
    } on ApiException catch (e) {
      if (mounted) {
        final message = switch (e.statusCode) {
          403 => 'Join the community to RSVP.',
          409 => 'This event is closed.',
          _ => 'Couldn\'t update your RSVP. Try again.',
        };
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t update your RSVP. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final cover = e.cover;

    final Widget rsvp = switch (e) {
      Event(cancelled: true) => _Banner('This event was cancelled.', colors.errorContainer, colors.onErrorContainer),
      Event(past: true) => _Banner('This event is over.', colors.surfaceContainerHighest, colors.onSurface),
      Event(myRsvp: RsvpStatus.going) => OutlinedButton.icon(
          onPressed: _busy ? null : () => _rsvp(false),
          icon: const Icon(Icons.check),
          label: const Text('You\'re going · Can\'t make it'),
        ),
      Event(myRsvp: RsvpStatus.waitlist, :final myWaitlistPosition) => OutlinedButton.icon(
          onPressed: _busy ? null : () => _rsvp(false),
          icon: const Icon(Icons.hourglass_top),
          label: Text('Waitlist #${myWaitlistPosition ?? '?'} · Leave waitlist'),
        ),
      Event(canRsvp: false) => Text('Join ${e.communityName} to RSVP.', style: textTheme.bodySmall),
      Event(isFull: true) => FilledButton.tonalIcon(
          onPressed: _busy ? null : () => _rsvp(true),
          icon: const Icon(Icons.playlist_add),
          label: const Text('Full · Join the waitlist'),
        ),
      _ => FilledButton.icon(
          onPressed: _busy ? null : () => _rsvp(true),
          icon: const Icon(Icons.event_available),
          label: const Text('I\'m going'),
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cover != null)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: MediaImage(
              MediaAttachment(id: cover.id, kind: MediaKind.image, url: cover.url, contentType: 'image/jpeg', sizeBytes: 0),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.title, style: textTheme.headlineSmall),
              InkWell(
                onTap: () => CommunityScreen.open(context, e.communityId),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('in ${e.communityName}', style: textTheme.labelLarge?.copyWith(color: colors.primary)),
                ),
              ),
              const SizedBox(height: 8),
              _Row(Icons.schedule, e.localWhen, e.inAnotherTimeZone ? 'There: ${e.eventWhen}' : null),
              if (e.isOnline)
                _Row(
                  Icons.videocam_outlined,
                  'Online',
                  e.onlineUrl ?? 'The link shows here once you\'re going.',
                  onTap: e.onlineUrl == null ? null : () => launchUrl(Uri.parse(e.onlineUrl!), mode: LaunchMode.externalApplication),
                )
              else
                _Row(Icons.place_outlined, e.placeName ?? 'In person', e.address),
              _Row(
                Icons.group_outlined,
                e.capacity == null ? '${e.goingCount} going' : '${e.goingCount} of ${e.capacity} going',
                [
                  if (e.spotsLeft != null && e.spotsLeft! > 0) '${e.spotsLeft} spots left',
                  if (e.waitlistCount > 0) '${e.waitlistCount} on the waitlist',
                ].join(' · ').ifEmpty(null),
              ),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: rsvp),
              if (e.description != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(e.description!)),
            ],
          ),
        ),
      ],
    );
  }
}

extension on String {
  String? ifEmpty(String? other) => isEmpty ? other : this;
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.title, this.subtitle, {this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        onTap: onTap,
      );
}

class _Banner extends StatelessWidget {
  const _Banner(this.text, this.background, this.foreground);
  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(color: foreground)),
      );
}

/// Who's going (and, for organisers, who's waiting).
class _Attendees extends ConsumerWidget {
  const _Attendees(this.event);
  final Event event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    Widget list(RsvpStatus status, String title) {
      final key = (eventId: event.id, status: status);
      final people = ref.watch(attendeesProvider(key));
      final items = people.value?.items ?? const <EventAttendee>[];
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text(title, style: textTheme.titleSmall)),
          for (final (i, a) in items.indexed)
            ListTile(
              leading: UserAvatar.of(a.user),
              title: Text(a.user.shownName),
              trailing: status == RsvpStatus.waitlist ? Text('#${i + 1}') : null,
              onTap: () => ProfileScreen.open(context, a.user.id),
            ),
          if (people.value?.hasMore ?? false)
            TextButton(
              onPressed: () => ref.read(attendeesProvider(key).notifier).loadMore(),
              child: const Text('More'),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        list(RsvpStatus.going, 'Going'),
        if (event.canManage) list(RsvpStatus.waitlist, 'Waitlist'),
        const SizedBox(height: 24),
      ],
    );
  }
}
