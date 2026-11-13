import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/data/services/service_providers.dart';
import 'package:news_feed_flutter/events/event.dart';
import 'package:news_feed_flutter/events/event_screen.dart';
import 'package:news_feed_flutter/events/events_api.dart';
import 'package:news_feed_flutter/events/events_providers.dart';
import 'package:news_feed_flutter/session/current_user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 16 Nov 2026, 00:30 UTC = 06:00 in India (UTC+5:30).
final start = DateTime.utc(2026, 11, 16, 0, 30);

Map<String, dynamic> event({
  String? myRsvp,
  int? position,
  int going = 1,
  int? capacity = 20,
  bool canManage = false,
  bool canRsvp = true,
  bool cancelled = false,
  String kind = 'in_person',
  String? onlineUrl,
}) =>
    {
      'id': 7,
      'community': {'id': 9, 'name': 'Runners', 'slug': 'runners'},
      'title': 'Sunday 10K',
      'description': 'Meet at the gate.',
      'startsAt': start.millisecondsSinceEpoch,
      'endsAt': start.add(const Duration(hours: 2)).millisecondsSinceEpoch,
      'timeZone': 'Asia/Kolkata',
      'utcOffsetMinutes': 330,
      'location': {'kind': kind, 'placeName': 'Cubbon Park', 'address': 'Bengaluru', 'onlineUrl': onlineUrl},
      'capacity': capacity,
      'goingCount': going,
      'waitlistCount': 0,
      'spotsLeft': capacity == null ? null : capacity - going,
      'cover': null,
      'cancelled': cancelled,
      'past': false,
      'myRsvp': myRsvp,
      'myWaitlistPosition': position,
      'canManage': canManage,
      'canRsvp': canRsvp,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.Request> requests;
  late Map<String, dynamic> served;
  late Map<String, dynamic> afterRsvp;

  setUp(() {
    SharedPreferences.setMockInitialValues({'id': 1, 'username': 'me', 'followerCount': 0});
    requests = [];
    served = event();
    afterRsvp = event(myRsvp: 'going', going: 2);
  });

  http.Client server() => MockClient((request) async {
        requests.add(request);
        http.Response json(Object? body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status,
            headers: {'content-type': 'application/json; charset=utf-8'});
        final path = request.url.path;
        if (path == '/events/7/rsvp') return json(request.method == 'PUT' ? afterRsvp : event());
        if (path == '/events/7') return json(served);
        if (path == '/events/7/attendees') return json({'items': [], 'nextCursor': null});
        if (path == '/communities/9/events' || path == '/events/upcoming') return json({'items': [], 'nextCursor': null});
        if (path == '/communities/9/events' && request.method == 'POST') return json(served, 201);
        return json({'error': 'not found'}, 404);
      });

  test('an event keeps its own clock: 06:00 in India, whatever this device\'s zone', () {
    final e = Event.fromJson(event());
    expect(e.startsAt, start);
    expect((e.eventClockStart.hour, e.eventClockStart.minute), (6, 0));
    expect(e.eventWhen, 'Mon 16 Nov · 06:00 – 08:00 (Asia/Kolkata)');
    expect(e.localStart, start.toLocal());
    expect(e.isFull, isFalse);
    expect(Event.fromJson(event(capacity: 1)).isFull, isTrue);
    expect(Event.fromJson(event(capacity: null)).spotsLeft, isNull);
  });

  test('a draft is sent as instants plus the zone, and only the fields of its kind of place', () {
    final draft = EventDraft(
      title: 'Strength class',
      startsAt: start,
      endsAt: start.add(const Duration(hours: 1)),
      timeZone: 'Asia/Kolkata',
      online: true,
      onlineUrl: 'https://meet.test/x',
    );
    expect(draft.toJson(), {
      'title': 'Strength class',
      'description': null,
      'startsAt': start.millisecondsSinceEpoch,
      'endsAt': start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      'timeZone': 'Asia/Kolkata',
      'location': {'kind': 'online', 'onlineUrl': 'https://meet.test/x'},
      'capacity': null,
    });
  });

  test('RSVPing updates the event from the server\'s answer', () async {
    final container = ProviderContainer.test(overrides: [apiHttpClientProvider.overrideWithValue(server())]);
    await container.read(currentUserProvider.future);
    final sub = container.listen(eventProvider(7), (_, _) {});
    await container.read(eventProvider(7).future);
    await container.read(eventProvider(7).notifier).rsvp();
    expect((sub.read().value!.myRsvp, sub.read().value!.goingCount), (RsvpStatus.going, 2));
    expect(requests.last.method, 'PUT');
  });

  Future<void> show(WidgetTester tester) async {
    final container = ProviderContainer.test(overrides: [apiHttpClientProvider.overrideWithValue(server())]);
    await tester.runAsync(() => container.read(currentUserProvider.future));
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: EventScreen(eventId: 7))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }

  testWidgets('a member can say they\'re going', (tester) async {
    await show(tester);
    expect(find.text('I\'m going'), findsOneWidget);
    expect(find.text('1 of 20 going'), findsOneWidget);
    expect(find.text('Cubbon Park'), findsOneWidget);
    await tester.tap(find.text('I\'m going'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(find.text('You\'re going · Can\'t make it'), findsOneWidget);
  });

  testWidgets('a full event offers the waitlist; on it, your place shows', (tester) async {
    served = event(capacity: 1, going: 1);
    afterRsvp = event(capacity: 1, going: 1, myRsvp: 'waitlist', position: 3);
    await show(tester);
    expect(find.text('Full · Join the waitlist'), findsOneWidget);
    await tester.tap(find.text('Full · Join the waitlist'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(find.text('Waitlist #3 · Leave waitlist'), findsOneWidget);
  });

  testWidgets('an online event hides its link until you\'re going', (tester) async {
    served = event(kind: 'online');
    await show(tester);
    expect(find.text('The link shows here once you\'re going.'), findsOneWidget);
  });

  testWidgets('non-members are asked to join, and get no organiser menu', (tester) async {
    served = event(canRsvp: false);
    await show(tester);
    expect(find.text('Join Runners to RSVP.'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets('a cancelled event says so, and has nothing left to edit', (tester) async {
    served = event(cancelled: true, canManage: true);
    await show(tester);
    expect(find.text('This event was cancelled.'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets('organisers get Edit and Cancel', (tester) async {
    served = event(canManage: true);
    await show(tester);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
  });
}
