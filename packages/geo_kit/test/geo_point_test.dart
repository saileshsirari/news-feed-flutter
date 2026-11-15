import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_kit/geo_kit.dart';
import 'package:latlong2/latlong.dart';

const cubbon = GeoPoint(12.9763, 77.5929);
const mgRoad = GeoPoint(12.9756, 77.6066);

void main() {
  test('distance along the surface matches the server (and PostGIS): 1.49 km', () {
    expect(cubbon.distanceKm(mgRoad), closeTo(1.488, 0.005));
    expect(cubbon.distanceKm(cubbon), 0);
    expect(cubbon.distanceKm(const GeoPoint(51.5074, -0.1278)), inInclusiveRange(7900, 8100)); // London
  });

  test('rounding: 2 places is about a kilometre', () {
    expect(cubbon.rounded(), const GeoPoint(12.98, 77.59));
    expect(cubbon.rounded(3), const GeoPoint(12.976, 77.593));
    expect(cubbon.distanceKm(cubbon.rounded()), lessThan(1));
  });

  test('a map panned past the 180° line comes back as a real longitude', () {
    expect(GeoPoint.fromLatLng(const LatLng(-17.7, 190)), const GeoPoint(-17.7, -170));
    expect(GeoPoint.fromLatLng(const LatLng(10, -185)), const GeoPoint(10, 175));
  });

  test('distances read the way people say them', () {
    expect(formatDistance(0.33, unit: DistanceUnit.km), '350 m');
    expect(formatDistance(1.488, unit: DistanceUnit.km), '1.5 km');
    expect(formatDistance(17.2, unit: DistanceUnit.km), '17 km');
  });

  test('in miles where road signs use them', () {
    expect(formatDistance(0.12, unit: DistanceUnit.miles), '400 ft');
    expect(formatDistance(1.488, unit: DistanceUnit.miles), '0.9 mi');
    expect(formatDistance(17.2, unit: DistanceUnit.miles), '11 mi');
  });

  test('km or miles from the locale\'s country', () {
    expect(DistanceUnit.forLocale(const Locale('en', 'IN')), DistanceUnit.km);
    expect(DistanceUnit.forLocale(const Locale('hi', 'IN')), DistanceUnit.km);
    expect(DistanceUnit.forLocale(const Locale('de', 'DE')), DistanceUnit.km);
    expect(DistanceUnit.forLocale(const Locale('en', 'US')), DistanceUnit.miles);
    expect(DistanceUnit.forLocale(const Locale('en', 'GB')), DistanceUnit.miles);
    expect(DistanceUnit.forLocale(const Locale('en')), DistanceUnit.km);
  });

  testWidgets('without a unit, the device\'s region decides', (tester) async {
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
    expect(formatDistance(0.3), '0.2 mi');
    tester.platformDispatcher.localeTestValue = const Locale('hi', 'IN');
    expect(formatDistance(0.3), '300 m');
    expect(defaultMapView().center, const GeoPoint(28.61, 77.21));
  });

  test('a map opens on the device\'s country, or the world', () {
    final india = defaultMapView(const Locale('en', 'IN'));
    expect(india.center, const GeoPoint(28.61, 77.21)); // Delhi
    expect(defaultMapView(const Locale('fr', 'FR')).center.lat, closeTo(46.6, 0.1));
    expect(defaultMapView(const Locale('en', 'US')).zoom, lessThan(india.zoom));
    final world = defaultMapView(const Locale('xx', 'ZZ'));
    expect(world.center, const GeoPoint(20, 0));
    expect(world.zoom, 2);
  });

  test('a place from the server', () {
    final p = Place.fromJson({'name': 'Cubbon Park', 'address': 'Bengaluru', 'lat': 12.9763, 'lng': 77.5929});
    expect(p.point, cubbon);
    expect(p.name, 'Cubbon Park');
  });
}
