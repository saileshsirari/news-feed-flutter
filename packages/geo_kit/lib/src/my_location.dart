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

/// The device's location, asked for only when the person taps "Near me",
/// and only roughly:
///
/// * [LocationAccuracy.low] is cell towers and Wi-Fi, not GPS ("approximate
///   location" on Android, which is all the app's manifest asks for). It's
///   quicker and kinder on the battery too.
/// * Then rounded to [decimals] places (2: about a kilometre) before
///   anything else in the app sees it, so even our own server only ever
///   learns "around Indiranagar".
class DeviceLocation implements LocationSource {
  const DeviceLocation({this.decimals = 2});

  final int decimals;

  @override
  Future<GeoPoint> current() async {
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
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 15)),
      );
      return GeoPoint(position.latitude, position.longitude).rounded(decimals);
    } on Exception {
      throw const LocationUnavailable('Couldn\'t find where you are. Try again, or pick a place on the map.');
    }
  }
}
