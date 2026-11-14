import 'geo_point.dart';

/// A named spot: "Cubbon Park", its address, and where it is.
class Place {
  const Place({required this.name, required this.point, this.address});

  final String name;
  final String? address;
  final GeoPoint point;

  factory Place.fromJson(Map<String, dynamic> json) => Place(
        name: json['name'] as String,
        address: json['address'] as String?,
        point: GeoPoint((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble()),
      );
}

/// Words to places and back. The app supplies one (ours goes through our
/// server to OpenStreetMap), so this package never talks to a server itself.
abstract interface class PlaceSearch {
  /// Places matching [query], best first; [near] favours ones close by.
  Future<List<Place>> search(String query, {GeoPoint? near});

  /// What's at [point] (a dropped pin), or null when nothing is (open sea).
  Future<Place?> reverse(GeoPoint point);
}
