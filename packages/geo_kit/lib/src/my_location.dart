import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'geo_point.dart';

/// Why there's no location: shown to the person, with a way to fix it when
/// there is one.
class LocationUnavailable implements Exception {
  const LocationUnavailable(this.message, {this.fix});

  final String message;

  /// Opens the settings that would fix it; null when nothing would.
  final Future<bool> Function()? fix;

  @override
  String toString() => message;
}

/// Where the device is, roughly. An interface so screens can be tested (and
/// a later app can feed in, say, a ride's live position).
abstract interface class LocationSource {
  /// Throws [LocationUnavailable] when switched off or not allowed.
  Future<GeoPoint> current();
}

/// A location source that also says how sure it is: a GPS fix is good to
/// a few metres; "approximate location" (Android lets people choose it)
/// only to a kilometre or more. Screens that need the exact spot (a taxi
/// pickup) use it to say "drag the pin to where you are".
abstract interface class AccurateLocationSource implements LocationSource {
  /// The point, and roughly how far off it might be, in metres.
  Future<({GeoPoint point, double accuracyMetres})> currentWithAccuracy();
}

/// The device's location, asked for only when the person taps "Near me",
/// and only roughly:
///
/// * [LocationAccuracy.low] is cell towers and Wi-Fi, not GPS ("approximate
///   location" on Android, which is all the app's manifest asks for). It's
///   quicker and kinder on the battery too.
/// * Then rounded to [decimals] places (2: about a kilometre) before
///   anything else in the app sees it, so even our own server only ever
///   learns "around Indiranagar".
///
/// [precise]: GPS, for a taxi driver's position while on duty (the rider
/// must see the car move, and the app shares it only during a trip). Needs
/// the precise-location permission; if the person grants only approximate,
/// the answer is approximate.
class DeviceLocation implements AccurateLocationSource {
  const DeviceLocation({this.decimals = 2, this.precise = false});

  final int decimals;
  final bool precise;

  @override
  Future<GeoPoint> current() async => (await currentWithAccuracy()).point;

  @override
  Future<({GeoPoint point, double accuracyMetres})> currentWithAccuracy() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable('Location is switched off on this device.', fix: Geolocator.openLocationSettings);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    switch (permission) {
      case LocationPermission.denied:
        throw const LocationUnavailable('Location wasn\'t allowed. You can pick a place on the map instead.');
      case LocationPermission.deniedForever:
        throw const LocationUnavailable('Location is turned off for this app.', fix: Geolocator.openAppSettings);
      case LocationPermission.whileInUse || LocationPermission.always || LocationPermission.unableToDetermine:
        break;
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: precise ? LocationAccuracy.high : LocationAccuracy.low,
          timeLimit: const Duration(seconds: 15),
        ),
      );
      return (
        point: GeoPoint(position.latitude, position.longitude).rounded(decimals),
        accuracyMetres: position.accuracy,
      );
    } on Exception {
      throw const LocationUnavailable('Couldn\'t find where you are. Try again, or pick a place on the map.');
    }
  }
}

/// The device's position as it moves, for as long as it's listened to: a
/// taxi driver on duty. Unlike [LocationSource], which answers once.
abstract interface class LocationTracker {
  /// Positions every [every] or so. On Android this runs as a *foreground
  /// service* with an ongoing notification ([notificationTitle],
  /// [notificationText]): Android's rule for apps that keep using location
  /// when they're not on screen, so the person can always see it's on and
  /// stop it. Cancelling the subscription stops it and the notification.
  Stream<GeoPoint> track({required Duration every, required String notificationTitle, required String notificationText});
}

/// GPS through geolocator. Permission is asked first by [DeviceLocation]
/// (the "while using the app" kind is enough: a foreground service started
/// while the app is open may keep using it).
class DeviceLocationTracker implements LocationTracker {
  const DeviceLocationTracker({this.decimals = 5});

  final int decimals;

  @override
  Stream<GeoPoint> track({required Duration every, required String notificationTitle, required String notificationText}) {
    final LocationSettings settings = switch (defaultTargetPlatform) {
      _ when kIsWeb => const LocationSettings(accuracy: LocationAccuracy.high),
      TargetPlatform.android => AndroidSettings(
        accuracy: LocationAccuracy.high,
        intervalDuration: every,
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: notificationTitle,
          notificationText: notificationText,
          notificationChannelName: 'On duty (location)',
          // Keeps the CPU (not the screen) awake so positions keep coming.
          enableWakeLock: true,
          setOngoing: true,
        ),
      ),
      TargetPlatform.iOS => AppleSettings(
        accuracy: LocationAccuracy.high,
        // Phase 1 on iPhone: while the app is open (background needs Xcode capabilities).
        allowBackgroundLocationUpdates: false,
      ),
      _ => const LocationSettings(accuracy: LocationAccuracy.high),
    };
    return Geolocator.getPositionStream(
      locationSettings: settings,
    ).map((p) => GeoPoint(p.latitude, p.longitude).rounded(decimals));
  }
}
