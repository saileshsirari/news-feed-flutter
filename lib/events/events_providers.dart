import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/paged_list.dart';
import 'event.dart';
import 'events_api.dart';

/// A community's events: upcoming (soonest first) or past (latest first).
class CommunityEventsNotifier extends AsyncNotifier<PagedList<Event>> with Paging<Event> {
  CommunityEventsNotifier(this.key);
  final ({int communityId, bool past}) key;

  @override
  Future<EventPage<Event>> fetch(String? cursor) =>
      ref.read(eventsApiProvider).forCommunity(key.communityId, past: key.past, cursor: cursor);

  @override
  Future<PagedList<Event>> build() {
    ref.watch(eventsApiProvider);
    return firstPage();
  }
}

final communityEventsProvider = AsyncNotifierProvider.autoDispose
    .family<CommunityEventsNotifier, PagedList<Event>, ({int communityId, bool past})>(CommunityEventsNotifier.new);

/// What's coming up across all your communities.
class UpcomingEventsNotifier extends AsyncNotifier<PagedList<Event>> with Paging<Event> {
  @override
  Future<EventPage<Event>> fetch(String? cursor) => ref.read(eventsApiProvider).upcoming(cursor: cursor);

  @override
  Future<PagedList<Event>> build() {
    ref.watch(eventsApiProvider);
    return firstPage();
  }
}

final upcomingEventsProvider =
    AsyncNotifierProvider.autoDispose<UpcomingEventsNotifier, PagedList<Event>>(UpcomingEventsNotifier.new);

/// One event, and RSVPing or cancelling it.
class EventNotifier extends AsyncNotifier<Event> {
  EventNotifier(this.id);
  final int id;

  EventsApi get _api => ref.read(eventsApiProvider);

  @override
  Future<Event> build() => ref.watch(eventsApiProvider).get(id);

  Future<void> rsvp() => _apply(() => _api.rsvp(id));
  Future<void> unrsvp() => _apply(() => _api.unrsvp(id));
  Future<void> cancel() => _apply(() => _api.cancel(id));

  /// After an edit made on the edit screen.
  void show(Event event) {
    state = AsyncData(event);
    _refreshLists(event.communityId);
  }

  Future<void> _apply(Future<Event> Function() action) async {
    final event = await action();
    if (!ref.mounted) return;
    state = AsyncData(event);
    _refreshLists(event.communityId);
  }

  /// Counts and RSVPs shown in lists changed too.
  void _refreshLists(int communityId) {
    ref.invalidate(communityEventsProvider((communityId: communityId, past: false)));
    ref.invalidate(upcomingEventsProvider);
    for (final status in RsvpStatus.values) {
      ref.invalidate(attendeesProvider((eventId: id, status: status)));
    }
  }
}

final eventProvider = AsyncNotifierProvider.autoDispose.family<EventNotifier, Event, int>(EventNotifier.new);

/// Who's going (or waiting: organisers only).
class AttendeesNotifier extends AsyncNotifier<PagedList<EventAttendee>> with Paging<EventAttendee> {
  AttendeesNotifier(this.key);
  final ({int eventId, RsvpStatus status}) key;

  @override
  Future<EventPage<EventAttendee>> fetch(String? cursor) =>
      ref.read(eventsApiProvider).attendees(key.eventId, status: key.status, cursor: cursor);

  @override
  Future<PagedList<EventAttendee>> build() {
    ref.watch(eventsApiProvider);
    return firstPage();
  }
}

final attendeesProvider = AsyncNotifierProvider.autoDispose
    .family<AttendeesNotifier, PagedList<EventAttendee>, ({int eventId, RsvpStatus status})>(AttendeesNotifier.new);
