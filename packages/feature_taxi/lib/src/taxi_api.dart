import 'dart:convert';

import 'package:app_core/config/app_config.dart';
import 'package:app_core/data/services/api_service.dart' show ApiException;
import 'package:app_core/data/services/service_providers.dart';
import 'package:app_core/session/current_user_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geo_kit/geo_kit.dart';
import 'package:http/http.dart' as http;
import 'package:payments_kit/payments_kit.dart';

import 'models.dart';

/// Why the server said no, in words for the person ("Taxi isn't available
/// here yet."), or a general line when it gave none.
String taxiErrorText(Object error) {
  if (error is ApiException) {
    try {
      final message = (jsonDecode(error.body) as Map<String, dynamic>)['error'];
      if (message is String) return message;
    } on Object {
      // Not JSON: fall through.
    }
  }
  return 'Something went wrong. Check your connection and try again.';
}

/// The server's taxi routes (see the server's taxiRoutes.ts), as the
/// signed-in [userId] (only read under development login; a real login is
/// trusted from its token).
class TaxiApi {
  TaxiApi(this._config, this._http, {required this.userId});

  final AppConfig _config;
  final http.Client _http;
  final int userId;

  Uri _uri(String path, [Map<String, Object?> query = const {}]) => Uri.parse('${_config.apiBaseUrl}$path').replace(
    queryParameters: {
      'userId': '$userId',
      for (final MapEntry(:key, :value) in query.entries)
        if (value != null) key: '$value',
    },
  );

  Future<Object?> _send(String method, String path, [Map<String, Object?>? body]) async {
    final request = http.Request(method, _uri(path));
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final res = await http.Response.fromStream(await _http.send(request));
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
    return res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
  }

  static Map<String, Object?> _place(GeoPoint p, [String? name]) => {'lat': p.lat, 'lng': p.lng, 'name': ?name};

  Trip _trip(Object? json) => Trip.fromJson(json! as Map<String, dynamic>);

  // Riders

  Future<Estimate> estimate(GeoPoint pickup, GeoPoint drop) async => Estimate.fromJson(
    (await _send('POST', '/taxi/estimate', {'pickup': _place(pickup), 'drop': _place(drop)}))! as Map<String, dynamic>,
  );

  Future<Trip> request(Place pickup, Place drop, {PaymentMethod payment = PaymentMethod.cash}) async => _trip(
    await _send('POST', '/taxi/trips', {
      'pickup': _place(pickup.point, pickup.name),
      'drop': _place(drop.point, drop.name),
      'payment': payment.name,
    }),
  );

  /// An order for a finished online ride's fare: open its checkout options
  /// in the payment sheet, then confirm through the payments routes.
  Future<PaymentOrder> pay(int tripId) async {
    final json = (await _send('POST', '/taxi/trips/$tripId/pay'))! as Map<String, dynamic>;
    return PaymentOrder.fromJson(json['order'] as Map<String, dynamic>);
  }

  /// Pay the driver in cash instead.
  Future<Trip> payInCash(int tripId) async => _trip(await _send('POST', '/taxi/trips/$tripId/pay-cash'));

  Future<Trip> cancel(int tripId) async => _trip(await _send('POST', '/taxi/trips/$tripId/cancel'));

  // Both

  Future<Trip> trip(int tripId) async => _trip(await _send('GET', '/taxi/trips/$tripId'));

  Future<Trip?> active() async {
    final json = await _send('GET', '/taxi/trips/active');
    return json == null ? null : _trip(json);
  }

  Future<List<Trip>> history() async => [for (final t in (await _send('GET', '/taxi/trips'))! as List) _trip(t)];

  // Drivers

  Future<Vehicle?> vehicle() async {
    final json = await _send('GET', '/taxi/driver');
    return json == null ? null : Vehicle.fromJson(json as Map<String, dynamic>);
  }

  Future<Vehicle> saveVehicle(String vehicle, String plate) async => Vehicle.fromJson(
    (await _send('PUT', '/taxi/driver', {'vehicle': vehicle, 'plate': plate}))! as Map<String, dynamic>,
  );

  /// Where I am, while on duty. Answers whether I'm inside a service area (online).
  Future<({bool online, String? areaName})> ping(GeoPoint p) async {
    final json = (await _send('POST', '/taxi/driver/location', {'lat': p.lat, 'lng': p.lng}))! as Map<String, dynamic>;
    return (online: json['online'] == true, areaName: (json['area'] as Map<String, dynamic>?)?['name'] as String?);
  }

  Future<void> offline() async => _send('POST', '/taxi/driver/offline');

  Future<Offer?> offer() async {
    final json = await _send('GET', '/taxi/driver/offer');
    return json == null ? null : Offer.fromJson(json as Map<String, dynamic>);
  }

  Future<Trip> accept(int tripId) async => _trip(await _send('POST', '/taxi/trips/$tripId/accept'));

  Future<void> decline(int tripId) async => _send('POST', '/taxi/trips/$tripId/decline');

  /// The driver's next move: arrived (at the pickup), start (rider's in), complete.
  Future<Trip> advance(int tripId, String step) async => _trip(await _send('POST', '/taxi/trips/$tripId/$step'));
}

final taxiApiProvider = Provider<TaxiApi>(
  (ref) => TaxiApi(
    ref.watch(appConfigProvider),
    ref.watch(apiHttpClientProvider),
    userId: ref.watch(currentUserProvider).requireValue!.id,
  ),
);

/// The driver's own position, precisely (GPS), only while on duty. An
/// override point for tests and the simulator-free demo.
final driverLocationProvider = Provider<LocationSource>((_) => const DeviceLocation(decimals: 5, precise: true));

/// "My location" in taxi's place picker: GPS, to ~1 m (5 decimals), and
/// how sure it is. Taxi only; the rest of the app keeps the ~1 km location.
final pickupLocationProvider = Provider<AccurateLocationSource>(
  (_) => const DeviceLocation(decimals: 5, precise: true),
);
