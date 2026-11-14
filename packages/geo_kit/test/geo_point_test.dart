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
    expect(formatDistance(0.33), '350 m');
    expect(formatDistance(1.488), '1.5 km');
    expect(formatDistance(17.2), '17 km');
  });

  test('a place from the server', () {
    final p = Place.fromJson({'name': 'Cubbon Park', 'address': 'Bengaluru', 'lat': 12.9763, 'lng': 77.5929});
    expect(p.point, cubbon);
    expect(p.name, 'Cubbon Park');
  });
}
