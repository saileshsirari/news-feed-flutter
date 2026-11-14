import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geo_kit/geo_kit.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../data/services/api_service.dart' show ApiException;
import '../data/services/service_providers.dart';
import '../session/current_user_provider.dart';

/// geo_kit's place search, through our server (/geo/search, /geo/reverse),
/// which asks OpenStreetMap and caches the answer. The phone never talks to
/// OpenStreetMap's search itself, so it never learns who's searching.
class GeocodingApi implements PlaceSearch {
  GeocodingApi(this._config, this._http, {required this.userId});

  final AppConfig _config;
  final http.Client _http;
  final int userId;

  Future<Object?> _get(String path, Map<String, Object?> query) async {
    final uri = Uri.parse('${_config.apiBaseUrl}$path').replace(queryParameters: {
      'userId': '$userId',
      for (final MapEntry(:key, :value) in query.entries)
        if (value != null) key: '$value',
    });
    final res = await _http.get(uri);
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  @override
  Future<List<Place>> search(String query, {GeoPoint? near}) async {
    // Only "around here" goes with a search, never the exact spot.
    final around = near?.rounded(1);
    return [
      for (final p in (await _get('/geo/search', {'q': query, 'lat': around?.lat, 'lng': around?.lng}))! as List)
        Place.fromJson(p as Map<String, dynamic>),
    ];
  }

  @override
  Future<Place?> reverse(GeoPoint point) async {
    final json = await _get('/geo/reverse', {'lat': point.lat, 'lng': point.lng});
    return json == null ? null : Place.fromJson(json as Map<String, dynamic>);
  }
}

final placeSearchProvider = Provider<PlaceSearch>(
  (ref) => GeocodingApi(
    ref.watch(appConfigProvider),
    ref.watch(apiHttpClientProvider),
    userId: ref.watch(currentUserProvider).requireValue!.id,
  ),
);

/// Map pictures: OpenStreetMap's, naming this app as its policy asks.
final mapTilesProvider = Provider<MapTiles>(
  (_) => const MapTiles.openStreetMap(userAgentPackageName: 'com.newsfeed.news_feed_flutter'),
);

/// The device's location, roughly (to about a kilometre; see DeviceLocation).
final locationSourceProvider = Provider<LocationSource>((_) => const DeviceLocation());
