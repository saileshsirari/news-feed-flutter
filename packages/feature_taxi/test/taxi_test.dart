import 'dart:convert';

import 'package:app_core/app_core.dart';
import 'package:app_core/data/services/service_providers.dart';
import 'package:app_core/data/services/socket_provider.dart';
import 'package:app_core/geo/geo_services.dart';
import 'package:app_core/session/current_user_provider.dart';
import 'package:app_core/testing/fake_socket.dart';
import 'package:feature_taxi/feature_taxi.dart';
import 'package:feature_taxi/src/car_marker.dart';
import 'package:feature_taxi/src/models.dart';
import 'package:feature_taxi/src/navigation_link.dart';
import 'package:feature_taxi/src/taxi_api.dart';
import 'package:feature_taxi/src/taxi_controllers.dart';
import 'package:feature_taxi/src/taxi_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_kit/geo_kit.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const connaughtPlace = Place(name: 'Connaught Place', point: GeoPoint(28.6315, 77.2167));
const igiAirport = Place(name: 'IGI Airport T3', point: GeoPoint(28.5562, 77.1));
const jaipur = Place(name: 'Hawa Mahal', point: GeoPoint(26.9239, 75.8267));

const delhi = {'id': 'delhi-ncr', 'name': 'Delhi NCR', 'timeZone': 'Asia/Kolkata', 'currency': 'INR'};
const fare = {'amountMinor': 39600, 'currency': 'INR'};

/// A small stand-in for the server's taxi routes, with one ride whose
/// status the test moves (as the server and the other phone would).
class FakeTaxiServer {
  FakeTaxiServer({this.me = 1});

  final int me;
  final asked = <String>[];
  final pings = <Map<String, dynamic>>[];
  Map<String, dynamic>? trip;
  Map<String, dynamic>? vehicle;
  Map<String, dynamic>? offer;

  Map<String, dynamic> newTrip({required String status, bool asDriver = false}) => trip = {
    'id': 7,
    'role': asDriver ? 'driver' : 'rider',
    'status': status,
    'area': delhi,
    'pickup': {'lat': 28.6315, 'lng': 77.2167, 'name': 'Connaught Place'},
    'drop': {'lat': 28.5562, 'lng': 77.1, 'name': 'IGI Airport T3'},
    'distanceM': 19088,
    'durationS': 3123,
    'fare': fare,
    'payment': 'cash',
    'routing': 'straight-line',
    'requestedAt': DateTime.utc(2026, 11, 15, 6, 30).millisecondsSinceEpoch,
    'completedAt': null,
    'cancelledBy': null,
    'cancelReason': null,
    'driver': null,
    'driverLocation': null,
    'pickupEtaS': null,
    'rider': asDriver ? {'id': 1, 'name': 'Asha'} : null,
  };

  /// A driver took it (what the server says after "accept").
  void accepted() {
    trip!['status'] = 'accepted';
    trip!['driver'] = {'id': 11, 'name': 'Ravi', 'vehicle': 'White Swift Dzire', 'plate': 'DL 1C AB 1234'};
    trip!['driverLocation'] = {'lat': 28.6315, 'lng': 77.221, 'at': 0};
    trip!['pickupEtaS'] = 120;
  }

  http.Client client() => MockClient((request) async {
    final path = request.url.path;
    asked.add('${request.method} $path');
    http.Response json(Object? body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    final body = request.body.isEmpty ? null : jsonDecode(request.body) as Map<String, dynamic>;
    switch ((request.method, path)) {
      case ('POST', '/taxi/estimate'):
        if ((body!['pickup']['lat'] as num) < 27) return json({'error': 'Taxi isn\'t available here yet.'}, 422);
        return json({
          'area': delhi,
          'distanceM': 19088,
          'durationS': 3123,
          'fare': fare,
          'routing': 'straight-line',
          'payment': 'cash',
        });
      case ('POST', '/taxi/trips'):
        return json(newTrip(status: 'offered'), 201);
      case ('GET', '/taxi/trips/active'):
        final going = trip != null && !['completed', 'cancelled'].contains(trip!['status']);
        return json(going ? trip : null);
      case ('GET', '/taxi/trips'):
        return json([?trip]);
      case ('GET', '/taxi/trips/7'):
        return json(trip);
      case ('POST', '/taxi/trips/7/cancel'):
        trip!['status'] = 'cancelled';
        trip!['cancelledBy'] = trip!['role'];
        return json(trip);
      case ('POST', '/taxi/trips/7/accept'):
        newTrip(status: 'accepted', asDriver: true);
        return json(trip);
      case ('POST', '/taxi/trips/7/decline'):
        return json({'ok': true});
      case ('POST', '/taxi/trips/7/arrived'):
        trip!['status'] = 'arriving';
        return json(trip);
      case ('POST', '/taxi/trips/7/start'):
        trip!['status'] = 'in_progress';
        return json(trip);
      case ('POST', '/taxi/trips/7/complete'):
        trip!['status'] = 'completed';
        return json(trip);
      case ('GET', '/taxi/driver'):
        return json(vehicle);
      case ('PUT', '/taxi/driver'):
        return json(vehicle = {'vehicle': body!['vehicle'], 'plate': (body['plate'] as String).toUpperCase()});
      case ('POST', '/taxi/driver/location'):
        pings.add(body!);
        return json({'online': true, 'area': delhi});
      case ('POST', '/taxi/driver/offline'):
        return json({'ok': true});
      case ('GET', '/taxi/driver/offer'):
        return json(offer);
    }
    return http.Response('{"error":"not found"}', 404);
  });
}

class FixedLocation implements LocationSource {
  const FixedLocation(this.point);
  final GeoPoint point;
  @override
  Future<GeoPoint> current() async => point;
}

/// Lets requests and microtasks finish, then settles the frames. Not
/// pumpAndSettle alone: the progress bar while matching never settles.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void useIndianLocale(WidgetTester tester) {
  tester.platformDispatcher.localeTestValue = const Locale('en', 'IN');
  addTearDown(tester.platformDispatcher.clearLocaleTestValue);
}

void main() {
  late FakeTaxiServer server;
  late FakeSocket socket;
  late List<Uri> launched;

  setUp(() {
    SharedPreferences.setMockInitialValues({'id': 1, 'username': 'me', 'followerCount': 0});
    server = FakeTaxiServer();
    socket = FakeSocket();
    launched = [];
  });

  Future<ProviderContainer> show(WidgetTester tester, Widget home, {Place? pickup, Place? drop}) async {
    useIndianLocale(tester);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final container = ProviderContainer.test(
      overrides: [
        apiHttpClientProvider.overrideWithValue(server.client()),
        socketProvider.overrideWith((ref, userId) => socket),
        mapTilesProvider.overrideWithValue(MapTiles.none),
        driverLocationProvider.overrideWithValue(const FixedLocation(GeoPoint(28.632, 77.219))),
        driverPingIntervalProvider.overrideWithValue(const Duration(seconds: 4)),
        // A phone with Google Maps: the first link opens.
        linkLauncherProvider.overrideWithValue((link) async {
          launched.add(link);
          return true;
        }),
        choosePlaceProvider.overrideWithValue(
          (context, ref, {required pickup, initial, near}) async =>
              pickup ? (pickupPlace ?? connaughtPlace) : (dropPlace ?? igiAirport),
        ),
      ],
    );
    pickupPlace = pickup;
    dropPlace = drop;
    shown = container;
    await tester.runAsync(() => container.read(currentUserProvider.future));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: home),
      ),
    );
    await settle(tester);
    return container;
  }

  group('money and models', () {
    test('fares in their own currency, written the device\'s way', () {
      expect(const Fare(39600, 'INR').format(locale: 'en_IN'), '₹396');
      // Germany puts a (no-break) space before the euro sign.
      expect(const Fare(2150, 'EUR').format(locale: 'de_DE').replaceAll('\u00a0', ' '), '21,50 €');
      expect(const Fare(1925, 'USD').format(locale: 'en_US'), '\$19.25');
    });

    test('directions links: Google Maps on Android, Apple Maps on iPhone, the web link everywhere', () async {
      const igi = GeoPoint(28.5562, 77.1);
      final android = navigationLinks(igi, platform: TargetPlatform.android, isWeb: false);
      expect(android.map((u) => u.toString()), [
        'google.navigation:q=28.5562,77.1&mode=d',
        'https://www.google.com/maps/dir/?api=1&destination=28.5562%2C77.1&travelmode=driving&dir_action=navigate',
      ]);
      final iphone = navigationLinks(igi, platform: TargetPlatform.iOS, isWeb: false);
      expect(iphone.first.toString(), 'https://maps.apple.com/?daddr=28.5562%2C77.1&dirflg=d');
      expect(navigationLinks(igi, platform: TargetPlatform.android, isWeb: true), [android.last]);

      // No Google Maps app: the next link (the browser) is tried.
      final tried = <Uri>[];
      final opened = await openDirections(
        (link) async {
          tried.add(link);
          return link.scheme == 'https';
        },
        igi,
        platform: TargetPlatform.android,
      );
      expect(opened, isTrue);
      expect(tried, hasLength(2));
      expect(await openDirections((_) async => false, igi, platform: TargetPlatform.android), isFalse);
    });

    test('compass bearings', () {
      const cp = GeoPoint(28.6315, 77.2167);
      expect(bearing(cp, const GeoPoint(28.7, 77.2167)), closeTo(0, 0.01)); // north
      expect(bearing(cp, const GeoPoint(28.6315, 77.3)), closeTo(90, 0.1)); // east
      expect(bearing(cp, const GeoPoint(28.5, 77.2167)), closeTo(180, 0.01)); // south
      expect(bearing(cp, const GeoPoint(28.6315, 77.1)), closeTo(270, 0.1)); // west
    });

    test('statuses, including in_progress', () {
      expect(TripStatus.parse('in_progress'), TripStatus.inProgress);
      expect(TripStatus.parse('offered').isMatching, isTrue);
      expect(TripStatus.parse('arriving').hasDriver, isTrue);
      expect(formatDuration(3123), '53 min');
      expect(formatDuration(3700), '1 h 2 min');
    });

    test('the mini-app opens rides by link', () {
      final app = TaxiMiniApp();
      expect(app.info.id, 'taxi');
      expect(app.screenFor(AppLinks.ride(7)), isA<TripScreen>());
      expect(app.screenFor(Uri.parse('app://taxi/other/7')), isNull);
    });

    test('socket watches are counted, and the last one out sends unwatch', () {
      final s = FakeSocket();
      final a = s.watch({'type': 'watch_trip', 'tripId': 7}, {'type': 'unwatch_trip', 'tripId': 7});
      final b = s.watch({'type': 'watch_trip', 'tripId': 7}, {'type': 'unwatch_trip', 'tripId': 7});
      expect(s.watches.toList(), [
        {'type': 'watch_trip', 'tripId': 7},
      ]);
      a();
      a(); // twice is harmless
      expect(s.watches, hasLength(1));
      b();
      expect(s.watches, isEmpty);
    });
  });

  group('riding', () {
    taxiTest('choose pickup and drop-off, see the upfront fare, request', (tester) async {
      await show(tester, const TaxiHomeScreen());
      await tester.tap(find.text('Choose pickup'));
      await settle(tester);
      await tester.tap(find.text('Where to?'));
      await settle(tester);

      expect(find.text('₹396'), findsOneWidget);
      expect(find.textContaining('19 km · about 53 min · Delhi NCR'), findsOneWidget);
      expect(find.textContaining('Paid in cash'), findsOneWidget);

      await tester.tap(find.text('Request ride · ₹396'));
      await settle(tester);
      expect(server.asked, contains('POST /taxi/trips'));
      expect(find.text('Finding you a driver…'), findsOneWidget);
      // The trip screen tuned in to its live channel.
      expect(socket.watches, anyElement(equals({'type': 'watch_trip', 'tripId': 7})));
    });

    taxiTest('outside every area: says so', (tester) async {
      await show(tester, const TaxiHomeScreen(), pickup: jaipur);
      await tester.tap(find.text('Choose pickup'));
      await settle(tester);
      await tester.tap(find.text('Where to?'));
      await settle(tester);
      expect(find.text('Taxi isn\'t available here yet.'), findsOneWidget);
      expect(find.textContaining('Request ride'), findsNothing);
    });

    taxiTest('live: the driver accepts, moves, arrives; the ride ends with the cash fare', (tester) async {
      server.newTrip(status: 'offered');
      await show(tester, const TripScreen(tripId: 7));
      expect(find.text('Finding you a driver…'), findsOneWidget);

      server.accepted();
      socket.controller.add({'type': 'taxi_trip', 'tripId': 7, 'status': 'accepted'});
      await settle(tester);
      expect(find.text('Ravi is on the way'), findsOneWidget);
      expect(find.text('White Swift Dzire · DL 1C AB 1234'), findsOneWidget);
      expect(find.text('About 2 min away.'), findsOneWidget);
      // The car on the map, named after its driver, facing the pickup (due west of it).
      expect(find.byTooltip('Ravi'), findsOneWidget);
      double heading() => tester.widget<CarMarker>(find.byType(CarMarker)).headingDegrees;
      expect(heading(), closeTo(270, 1));

      // The car moves closer: no fetch, just the new position (and a new ETA).
      final fetches = server.asked.length;
      socket.controller.add({'type': 'taxi_driver_location', 'tripId': 7, 'lat': 28.6316, 'lng': 77.2168, 'at': 1});
      await settle(tester);
      expect(server.asked.length, fetches);
      expect(find.text('About 1 min away.'), findsOneWidget);
      // It drove west, a touch north: it faces that way.
      expect(heading(), closeTo(271.6, 0.5));

      // Someone else's trip: ignored.
      socket.controller.add({'type': 'taxi_trip', 'tripId': 8, 'status': 'completed'});
      await settle(tester);
      expect(server.asked.length, fetches);

      server.trip!['status'] = 'arriving';
      socket.controller.add({'type': 'taxi_trip', 'tripId': 7, 'status': 'arriving'});
      await settle(tester);
      expect(find.text('Your driver is here'), findsOneWidget);

      server.trip!
        ..['status'] = 'completed'
        ..['driverLocation'] = null;
      socket.controller.add({'type': 'taxi_trip', 'tripId': 7, 'status': 'completed'});
      await settle(tester);
      expect(find.text('You\'ve arrived'), findsOneWidget);
      expect(find.text('Please pay ₹396 in cash.'), findsOneWidget);
      expect(find.byType(CarMarker), findsNothing);
    });

    taxiTest('full map: the details slide down to a peek, and come back', (tester) async {
      server.newTrip(status: 'offered');
      server.accepted();
      await show(tester, const TripScreen(tripId: 7));
      final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      bool onScreen(Finder f) => tester.getTopLeft(f).dy < screenHeight;
      const car = 'White Swift Dzire · DL 1C AB 1234';

      expect(onScreen(find.text(car)), isTrue);
      await tester.tap(find.byTooltip('Full map'));
      await tester.pumpAndSettle();
      // The headline still peeks out at the bottom; the details are below the screen.
      expect(
        tester.getTopLeft(find.text('Ravi is on the way')).dy,
        inInclusiveRange(screenHeight * 0.85, screenHeight),
      );
      expect(onScreen(find.text(car)), isFalse);
      expect(find.byTooltip('Show details'), findsOneWidget);

      // Tapping the handle (or the button) brings them back.
      await tester.tap(find.bySemanticsLabel('Show or hide ride details'));
      await tester.pumpAndSettle();
      expect(onScreen(find.text(car)), isTrue);
      expect(find.byTooltip('Full map'), findsOneWidget);
    });

    taxiTest('no drivers nearby', (tester) async {
      server.newTrip(status: 'cancelled')
        ..['cancelledBy'] = 'system'
        ..['cancelReason'] = 'No drivers nearby';
      await show(tester, const TripScreen(tripId: 7));
      expect(find.text('No drivers nearby'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    taxiTest('cancelling asks first', (tester) async {
      server.newTrip(status: 'offered');
      await show(tester, const TripScreen(tripId: 7));
      await tester.tap(find.text('Cancel ride'));
      await settle(tester);
      await tester.tap(find.text('Cancel ride').last);
      await settle(tester);
      expect(server.asked, contains('POST /taxi/trips/7/cancel'));
      expect(find.text('Ride cancelled'), findsOneWidget);
    });

    taxiTest('history lists rides', (tester) async {
      server.newTrip(status: 'completed');
      await show(tester, const HistoryScreen());
      expect(find.text('Connaught Place → IGI Airport T3'), findsOneWidget);
      expect(find.text('₹396'), findsOneWidget);
    });
  });

  group('driving', () {
    Future<void> toDriveMode(WidgetTester tester) async {
      await tester.tap(find.text('Drive'));
      await settle(tester);
    }

    taxiTest('set up the car, go on duty: position pings and offers start', (tester) async {
      await show(tester, const TaxiHomeScreen());
      await toDriveMode(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Car (colour and model)'), 'White Swift Dzire');
      await tester.enterText(find.widgetWithText(TextField, 'Number plate'), 'dl 1c ab 1234');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('DL 1C AB 1234'), findsOneWidget);

      await tester.tap(find.text('On duty'));
      await settle(tester);
      expect(find.text('Taking rides in Delhi NCR'), findsOneWidget);
      expect(server.pings.single, {'lat': 28.632, 'lng': 77.219});
      expect(socket.watches, anyElement(equals({'type': 'watch_offers'})));

      // Every few seconds, another ping.
      await tester.pump(const Duration(seconds: 4));
      await settle(tester);
      expect(server.pings, hasLength(2));

      await tester.tap(find.text('On duty'));
      await settle(tester);
      expect(server.asked, contains('POST /taxi/driver/offline'));
      expect(socket.watches, isEmpty);
    });

    Map<String, Object?> offerJson({int seconds = 15}) => {
      'tripId': 7,
      'expiresAt': DateTime.now().add(Duration(seconds: seconds)).millisecondsSinceEpoch,
      'area': delhi,
      'pickupNear': {'lat': 28.63, 'lng': 77.22},
      'pickupDistanceM': 450,
      'dropNear': {'lat': 28.56, 'lng': 77.1},
      'distanceM': 19088,
      'durationS': 3123,
      'fare': fare,
    };

    taxiTest('an offer with a countdown; accept, then move the ride along', (tester) async {
      server.vehicle = {'vehicle': 'White Swift Dzire', 'plate': 'DL 1C AB 1234'};
      await show(tester, const TaxiHomeScreen());
      await toDriveMode(tester);
      await tester.tap(find.text('On duty'));
      await settle(tester);

      socket.controller.add({'type': 'taxi_offer', 'offer': offerJson()});
      await settle(tester);
      expect(find.text('New ride · ₹396'), findsOneWidget);
      expect(find.text('Pickup 450 m from you'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^1[45]s$')), findsOneWidget);
      expect(find.text('The exact pickup shows once you accept.'), findsOneWidget);

      await tester.tap(find.text('Accept'));
      await settle(tester);
      expect(server.asked, contains('POST /taxi/trips/7/accept'));
      expect(find.text('Drive to the pickup'), findsOneWidget);
      expect(find.text('Picking up Asha at Connaught Place.'), findsOneWidget);
      // Directions to the exact pickup, in the phone's maps app (the test runs as Android).
      await tester.tap(find.text('Navigate to pickup'));
      await settle(tester);
      expect(launched.single.toString(), 'google.navigation:q=28.6315,77.2167&mode=d');

      await tester.tap(find.text('I\'ve arrived'));
      await settle(tester);
      expect(find.text('Waiting for Asha'), findsOneWidget);
      await tester.tap(find.text('Start ride'));
      await settle(tester);
      expect(find.text('On the way to IGI Airport T3'), findsOneWidget);
      await tester.tap(find.text('Navigate to drop-off'));
      await settle(tester);
      expect(launched.last.toString(), 'google.navigation:q=28.5562,77.1&mode=d');
      await tester.tap(find.text('Complete ride'));
      await settle(tester);
      expect(find.text('Collect ₹396 in cash.'), findsOneWidget);
    });

    taxiTest('an offer not taken in time goes away', (tester) async {
      server.vehicle = {'vehicle': 'White Swift Dzire', 'plate': 'DL 1C AB 1234'};
      await show(tester, const TaxiHomeScreen());
      await toDriveMode(tester);
      await tester.tap(find.text('On duty'));
      await settle(tester);
      socket.controller.add({'type': 'taxi_offer', 'offer': offerJson(seconds: 1)});
      await settle(tester);
      expect(find.text('New ride · ₹396'), findsOneWidget);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1200)));
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
      expect(find.text('New ride · ₹396'), findsNothing);
      expect(find.text('Waiting for a ride request…'), findsOneWidget);
    });

    taxiTest('declining tells the server', (tester) async {
      server.vehicle = {'vehicle': 'White Swift Dzire', 'plate': 'DL 1C AB 1234'};
      await show(tester, const TaxiHomeScreen());
      await toDriveMode(tester);
      await tester.tap(find.text('On duty'));
      await settle(tester);
      socket.controller.add({'type': 'taxi_offer', 'offer': offerJson()});
      await settle(tester);
      await tester.tap(find.text('Decline'));
      await settle(tester);
      expect(server.asked, contains('POST /taxi/trips/7/decline'));
      expect(find.text('New ride · ₹396'), findsNothing);
    });
  });
}

Place? pickupPlace;
Place? dropPlace;

/// The container [show] made, closed after each test: closing it stops the
/// driver's ping timer and the live watches, as leaving the mini-app does.
ProviderContainer? shown;

/// A widget test that ends by leaving the screen and closing the providers.
void taxiTest(String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox());
    shown?.dispose();
    shown = null;
    await tester.pump();
  });
}
