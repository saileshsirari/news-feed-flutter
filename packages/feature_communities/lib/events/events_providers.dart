import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app_core/data/paged_list.dart';
import 'package:feature_communities/payments/checkout.dart';
import 'package:feature_communities/payments/payments_api.dart';
import 'package:feature_communities/events/event.dart';
import 'package:feature_communities/events/events_api.dart';

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

  /// Buys a ticket: a spot held and an order made (server), the payment
  /// sheet (Razorpay), then the sheet's answer passed to the server to check.
  /// Closing the sheet lets the held spot go at once, for someone else.
  /// Returns what the sheet answered.
  Future<CheckoutResult> buyTicket() async {
    final api = _api;
    final payments = ref.read(paymentsApiProvider);
    final checkout = ref.read(checkoutProvider);

    final (:event, :order) = await api.buyTicket(id);
    if (ref.mounted) state = AsyncData(event);
    final options = order.checkoutOptions;
    if (options == null) return const CheckoutFailed('This order can\'t be paid any more. Try again.');

    final result = await checkout.open(options);
    switch (result) {
      case CheckoutPaid():
        try {
          await payments.confirm(order.id, result);
        } on Object {
          // The money went through; Razorpay tells the server directly too
          // (its webhook), so the ticket arrives either way. Refresh below.
        }
      case CheckoutCancelled() || CheckoutFailed():
        await api.unrsvp(id); // let the held spot go
    }
    final now = await api.get(id);
    if (ref.mounted) {
      state = AsyncData(now);
      _refreshLists(now.communityId);
      ref.invalidate(myOrdersProvider);
    }
    return result;
  }
  /// Not going. A paid ticket is refunded if it's before the refund deadline.
  Future<void> unrsvp() async {
    await _apply(() => _api.unrsvp(id));
    if (ref.mounted) ref.invalidate(myOrdersProvider);
  }
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
