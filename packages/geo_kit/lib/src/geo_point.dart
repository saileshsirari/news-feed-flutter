import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// A spot on the earth: latitude (north-south, -90..90) and longitude
/// (east-west, -180..180), in degrees. The same as the server's src/geo.
class GeoPoint {
  const GeoPoint(this.lat, this.lng)
      : assert(lat >= -90 && lat <= 90),
        assert(lng >= -180 && lng <= 180);

  final double lat;
  final double lng;

  /// Mean earth radius (km), as the server and PostGIS use.
  static const earthRadiusKm = 6371.0088;

  /// Straight along the surface, by the haversine formula: Cubbon Park to
  /// MG Road is 1.49 km.
  double distanceKm(GeoPoint other) {
    double rad(double deg) => deg * math.pi / 180;
    final dLat = rad(other.lat - lat);
    final dLng = rad(other.lng - lng);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat)) * math.cos(rad(other.lat)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * earthRadiusKm * math.asin(math.min(1, math.sqrt(h)));
  }

  /// To [decimals] places: 2 is about a kilometre, 3 about a street, 4 a
  /// building. Sharing a rounded point says "around here", not "here".
  GeoPoint rounded([int decimals = 2]) {
    final f = math.pow(10, decimals);
    return GeoPoint((lat * f).round() / f, (lng * f).round() / f);
  }

  /// For flutter_map.
  LatLng get latLng => LatLng(lat, lng);

  static GeoPoint fromLatLng(LatLng p) => GeoPoint(p.latitude.clamp(-90, 90), _wrap(p.longitude));

  /// A map panned past 180° reports 190°; that's -170°.
  static double _wrap(double lng) => ((lng + 180) % 360 + 360) % 360 - 180;

  @override
  bool operator ==(Object other) => other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'GeoPoint(${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)})';
}

/// "350 m", "1.5 km", "17 km": precise when close, rounder when far.
String formatDistance(double km) {
  if (km < 1) return '${(km * 1000 / 50).round() * 50} m';
  if (km < 10) return '${km.toStringAsFixed(1)} km';
  return '${km.round()} km';
}
