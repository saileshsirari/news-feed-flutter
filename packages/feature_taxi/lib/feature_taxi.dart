/// Taxi as a mini-app: ask for a ride, watch the car come on the map, pay
/// in cash; and a simple driver mode (on duty, offers, the ride's steps).
/// The shell knows it only through [TaxiMiniApp]. See the server's
/// docs/TAXI.md for how matching and live tracking work.
library;

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'src/taxi_home_screen.dart';
import 'src/trip_screen.dart';
import 'taxi_info.dart';

export 'src/history_screen.dart' show HistoryScreen;
export 'src/taxi_home_screen.dart' show TaxiHomeScreen;
export 'src/trip_screen.dart' show TripScreen;
export 'taxi_info.dart';

class TaxiMiniApp extends MiniApp {
  @override
  MiniAppInfo get info => taxiInfo;

  @override
  Widget buildHome(BuildContext context) => const TaxiHomeScreen();

  /// `app://taxi/ride/<id>`.
  @override
  Widget? screenFor(Uri link) {
    return switch (AppLinks.idOf(link, 'ride')) {
      final id? => TripScreen(tripId: id),
      null => null,
    };
  }
}
