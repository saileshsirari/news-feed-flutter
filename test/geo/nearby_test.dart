import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_kit/geo_kit.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/communities/community.dart';
import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/service_providers.dart';
import 'package:news_feed_flutter/events/events_api.dart';
import 'package:news_feed_flutter/geo/geo_services.dart';
import 'package:news_feed_flutter/geo/nearby_screen.dart';
import 'package:news_feed_flutter/session/current_user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hands back [answer]: a point, or throws a LocationUnavailable.
class FakeLocation implements LocationSource {
  FakeLocation(this.answer);
  final Object answer;
  int asked = 0;

  @override
  Future<GeoPoint> current() async {
    asked++;
    if (answer case final LocationUnavailable e) throw e;
    return answer as GeoPoint;
  }
}

Map<String, dynamic> event({required int id, required String title, required double km}) => {
      'id': id,
      'community': {'id': 9, 'name': 'Runners', 'slug': 'runners'},
      'title': title,
      'startsAt': DateTime.utc(2026, 11, 16, 0, 30).millisecondsSinceEpoch,
      'endsAt': DateTime.utc(2026, 11, 16, 2, 30).millisecondsSinceEpoch,
      'timeZone': 'Asia/Kolkata',
      'utcOffsetMinutes': 330,
      'location': {'kind': 'in_person', 'placeName': title, 'latitude': 12.9756, 'longitude': 77.6066},
      'goingCount': 1,
      'waitlistCount': 0,
      'distanceKm': km,
    };

Map<String, dynamic> community() => {
      'id': 5,
      'slug': 'readers',
      'name': 'Indiranagar Readers',
      'visibility': 'private',
      'memberCount': 12,
      'area': {'name': 'Indiranagar, Bengaluru', 'lat': 12.97, 'lng': 77.64},
      'distanceKm': 5.2,
    };

void main() {
  late List<Uri> asked;

  setUp(() {
    SharedPreferences.setMockInitialValues({'id': 1, 'username': 'me', 'followerCount': 0});
    asked = [];
  });

  http.Client server() => MockClient((request) async {
        asked.add(request.url);
        http.Response json(Object? body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
        return switch (request.url.path) {
          '/events/nearby' => json([
              event(id: 1, title: 'Cubbon run', km: 0.3),
              event(id: 2, title: 'MG Road meetup', km: 1.49),
            ]),
          '/communities/nearby' => json([community()]),
          '/geo/search' => json([
              {'name': 'Cubbon Park', 'address': 'Bengaluru', 'lat': 12.9763, 'lng': 77.5929},
            ]),
          '/geo/reverse' => json(null),
          _ => http.Response('{"error":"not found"}', 404),
        };
      });

  Future<void> show(WidgetTester tester, LocationSource location) async {
    final container = ProviderContainer.test(overrides: [
      apiHttpClientProvider.overrideWithValue(server()),
      locationSourceProvider.overrideWithValue(location),
      mapTilesProvider.overrideWithValue(MapTiles.none),
    ]);
    // Signed in already, as on the real screen (the app opens it only then).
    await tester.runAsync(() => container.read(currentUserProvider.future));
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: NearbyScreen())));
    await settle(tester);
  }

  testWidgets('finds events around your (rounded) area, nearest first, with distances', (tester) async {
    final location = FakeLocation(const GeoPoint(12.98, 77.59));
    await show(tester, location);

    expect(location.asked, 1);
    final q = asked.singleWhere((u) => u.path == '/events/nearby').queryParameters;
    expect((q['lat'], q['lng'], q['radiusKm']), ('12.98', '77.59', '10.0'));
    expect(find.text('Cubbon run'), findsOneWidget);
    expect(find.textContaining('300 m'), findsOneWidget);
    expect(find.textContaining('1.5 km'), findsOneWidget);
  });

  testWidgets('communities, and a wider circle', (tester) async {
    await show(tester, FakeLocation(const GeoPoint(12.98, 77.59)));

    await tester.tap(find.text('Communities'));
    await settle(tester);
    expect(find.text('Indiranagar Readers'), findsOneWidget);
    expect(find.textContaining('5.2 km · Private · 12 members · Indiranagar, Bengaluru'), findsOneWidget);

    await tester.tap(find.text('25 km'));
    await settle(tester);
    expect(asked.last.path, '/communities/nearby');
    expect(asked.last.queryParameters['radiusKm'], '25.0');
  });

  testWidgets('on a map: a pin for each one', (tester) async {
    await show(tester, FakeLocation(const GeoPoint(12.98, 77.59)));
    await tester.tap(find.byTooltip('Show on a map'));
    await settle(tester);
    expect(find.byTooltip('Cubbon run'), findsOneWidget);
    expect(find.byTooltip('MG Road meetup'), findsOneWidget);
  });

  testWidgets('without location: says why, and offers to choose a place', (tester) async {
    await show(tester, FakeLocation(const LocationUnavailable('Location wasn\'t allowed.')));
    expect(find.text('Location wasn\'t allowed.'), findsOneWidget);
    expect(asked.where((u) => u.path == '/events/nearby'), isEmpty);

    await tester.tap(find.text('Choose a place'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'cubbon');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    await tester.tap(find.text('Cubbon Park').last);
    await settle(tester);
    await tester.tap(find.text('Use Cubbon Park'));
    await settle(tester);

    expect(find.text('Around Cubbon Park'), findsOneWidget);
    expect(asked.last.path, '/events/nearby');
    expect(asked.last.queryParameters['lat'], '12.9763');
  });

  test('place search sends only "around here" (to ~10 km) with the words', () async {
    final api = GeocodingApi(AppConfig.fromEnvironment(), server(), userId: 1);
    final found = await api.search('cubbon', near: const GeoPoint(12.9763, 77.5929));
    expect(found.single.name, 'Cubbon Park');
    expect((asked.last.queryParameters['lat'], asked.last.queryParameters['lng']), ('13.0', '77.6'));
    expect(await api.reverse(const GeoPoint(0, -30)), isNull);
  });

  test('a pinned event sends its point; a community reads its area', () {
    final draft = EventDraft(
      title: 'Run',
      startsAt: DateTime.utc(2026),
      endsAt: DateTime.utc(2026, 1, 1, 2),
      timeZone: 'UTC',
      online: false,
      placeName: 'Cubbon Park',
      point: const GeoPoint(12.9763, 77.5929),
    );
    expect(draft.toJson()['location'], containsPair('latitude', 12.9763));
    final c = Community.fromJson(community());
    expect(c.area!.name, 'Indiranagar, Bengaluru');
    expect(c.area!.point, const GeoPoint(12.97, 77.64));
    expect(c.distanceKm, 5.2);
  });
}

/// Lets the fake server's futures finish, then draws.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
  }
}
