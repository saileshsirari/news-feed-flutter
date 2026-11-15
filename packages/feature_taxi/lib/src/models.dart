import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geo_kit/geo_kit.dart';
import 'package:intl/intl.dart';

/// A price in whole minor units (paise, cents), in its own currency: a ride
/// in Berlin costs euros whoever's phone shows it. Never a double.
@immutable
class Fare {
  const Fare(this.amountMinor, this.currency);

  final int amountMinor;
  final String currency;

  factory Fare.fromJson(Map<String, dynamic> json) => Fare(json['amountMinor'] as int, json['currency'] as String);

  /// "₹396", "€21.50", "$19.25", written the way the device's region writes
  /// numbers ("₹1,00,000" in India, "100.000 €" in Germany).
  String format({String? locale}) {
    final whole = amountMinor % 100 == 0;
    final tag = Intl.verifiedLocale(
      locale ?? deviceLocale().toLanguageTag(),
      NumberFormat.localeExists,
      onFailure: (_) => 'en',
    );
    return NumberFormat.currency(
      locale: tag,
      name: currency,
      symbol: NumberFormat.simpleCurrency(name: currency).currencySymbol,
      decimalDigits: whole ? 0 : 2,
    ).format(amountMinor / 100);
  }

  @override
  String toString() => format();

  @override
  bool operator ==(Object other) => other is Fare && other.amountMinor == amountMinor && other.currency == currency;

  @override
  int get hashCode => Object.hash(amountMinor, currency);
}

/// Where taxi runs: "Delhi NCR", with its clock and money.
@immutable
class TaxiArea {
  const TaxiArea({required this.id, required this.name, required this.timeZone, required this.currency});

  final String id;
  final String name;
  final String timeZone;
  final String currency;

  factory TaxiArea.fromJson(Map<String, dynamic> json) => TaxiArea(
    id: json['id'] as String,
    name: json['name'] as String,
    timeZone: json['timeZone'] as String,
    currency: json['currency'] as String,
  );
}

/// "About 6.4 km, 17 min, ₹166": shown before asking for a ride. The fare
/// is upfront: what you see is what you pay (in cash, for now).
@immutable
class Estimate {
  const Estimate({
    required this.area,
    required this.distanceM,
    required this.durationS,
    required this.fare,
    required this.routing,
  });

  final TaxiArea area;
  final int distanceM;
  final int durationS;
  final Fare fare;

  /// "straight-line" means a rough guess from the distance as the crow flies.
  final String routing;

  factory Estimate.fromJson(Map<String, dynamic> json) => Estimate(
    area: TaxiArea.fromJson(json['area'] as Map<String, dynamic>),
    distanceM: json['distanceM'] as int,
    durationS: json['durationS'] as int,
    fare: Fare.fromJson(json['fare'] as Map<String, dynamic>),
    routing: json['routing'] as String? ?? 'straight-line',
  );
}

/// A trip's life, as the server's state machine has it (see docs/TAXI.md).
enum TripStatus {
  requested,
  offered,
  accepted,
  arriving,
  inProgress,
  completed,
  cancelled;

  static TripStatus parse(String s) => switch (s) {
    'in_progress' => inProgress,
    _ => values.byName(s),
  };

  /// Still looking for a driver.
  bool get isMatching => this == requested || this == offered;

  /// A driver is on it (their position is shared).
  bool get hasDriver => this == accepted || this == arriving || this == inProgress;

  bool get isOver => this == completed || this == cancelled;
}

@immutable
class TripDriver {
  const TripDriver({required this.id, required this.name, required this.vehicle, required this.plate});

  final int id;
  final String name;
  final String vehicle;
  final String plate;

  factory TripDriver.fromJson(Map<String, dynamic> json) => TripDriver(
    id: json['id'] as int,
    name: json['name'] as String,
    vehicle: json['vehicle'] as String? ?? '',
    plate: json['plate'] as String? ?? '',
  );
}

/// A ride, as its rider or its driver sees it (the server's TripView).
@immutable
class Trip {
  const Trip({
    required this.id,
    required this.isDriver,
    required this.status,
    required this.area,
    required this.pickup,
    required this.drop,
    required this.distanceM,
    required this.durationS,
    required this.fare,
    required this.requestedAt,
    this.pickupName,
    this.dropName,
    this.completedAt,
    this.cancelledBy,
    this.cancelReason,
    this.driver,
    this.driverLocation,
    this.pickupEtaS,
    this.riderName,
    this.driverHeading,
  });

  final int id;

  /// Seen by the driver (true) or the rider.
  final bool isDriver;
  final TripStatus status;
  final TaxiArea area;
  final GeoPoint pickup;
  final String? pickupName;
  final GeoPoint drop;
  final String? dropName;
  final int distanceM;
  final int durationS;
  final Fare fare;
  final DateTime requestedAt;
  final DateTime? completedAt;
  final String? cancelledBy;
  final String? cancelReason;
  final TripDriver? driver;

  /// Where the car is, while the ride is going (null otherwise).
  final GeoPoint? driverLocation;

  /// Rough seconds until the car reaches the pickup.
  final int? pickupEtaS;
  final String? riderName;

  /// Which way the car last moved (compass degrees, 0 = north), worked out
  /// on the phone from its last two positions; null before it has moved.
  final double? driverHeading;

  /// Which way to draw the car: the way it last moved, or else towards
  /// where it's going next (the pickup, then the drop-off).
  double get carHeading {
    final car = driverLocation;
    if (driverHeading != null || car == null) return driverHeading ?? 0;
    return bearing(car, status == TripStatus.inProgress ? drop : pickup);
  }

  factory Trip.fromJson(Map<String, dynamic> json) {
    GeoPoint point(Object? p) {
      final m = p! as Map<String, dynamic>;
      return GeoPoint((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
    }

    DateTime? time(Object? ms) => ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms as int);
    final pickup = json['pickup'] as Map<String, dynamic>;
    final drop = json['drop'] as Map<String, dynamic>;
    return Trip(
      id: json['id'] as int,
      isDriver: json['role'] == 'driver',
      status: TripStatus.parse(json['status'] as String),
      area: TaxiArea.fromJson(json['area'] as Map<String, dynamic>),
      pickup: point(pickup),
      pickupName: pickup['name'] as String?,
      drop: point(drop),
      dropName: drop['name'] as String?,
      distanceM: json['distanceM'] as int,
      durationS: json['durationS'] as int,
      fare: Fare.fromJson(json['fare'] as Map<String, dynamic>),
      requestedAt: time(json['requestedAt'])!,
      completedAt: time(json['completedAt']),
      cancelledBy: json['cancelledBy'] as String?,
      cancelReason: json['cancelReason'] as String?,
      driver: json['driver'] == null ? null : TripDriver.fromJson(json['driver'] as Map<String, dynamic>),
      driverLocation: json['driverLocation'] == null ? null : point(json['driverLocation']),
      pickupEtaS: json['pickupEtaS'] as int?,
      riderName: (json['rider'] as Map<String, dynamic>?)?['name'] as String?,
    );
  }

  Trip withDriverAt(GeoPoint p) => Trip(
    id: id,
    isDriver: isDriver,
    status: status,
    area: area,
    pickup: pickup,
    pickupName: pickupName,
    drop: drop,
    dropName: dropName,
    distanceM: distanceM,
    durationS: durationS,
    fare: fare,
    requestedAt: requestedAt,
    completedAt: completedAt,
    cancelledBy: cancelledBy,
    cancelReason: cancelReason,
    driver: driver,
    driverLocation: p,
    // The car moved: work the ETA out again, roughly (22 km/h, roads 1.35x the crow's path).
    pickupEtaS: status == TripStatus.accepted ? (p.distanceKm(pickup) * 1.35 / 22 * 3600).round() : pickupEtaS,
    riderName: riderName,
    // Only a real move (more than ~5 m) turns the car: GPS wobbles when parked.
    driverHeading: driverLocation != null && driverLocation!.distanceKm(p) > 0.005
        ? bearing(driverLocation!, p)
        : driverHeading,
  );

  /// "Connaught Place", or the spot's coordinates when it had no name.
  String get pickupLabel => pickupName ?? _near(pickup);
  String get dropLabel => dropName ?? _near(drop);
  static String _near(GeoPoint p) => 'Near ${p.lat.toStringAsFixed(2)}, ${p.lng.toStringAsFixed(2)}';
}

/// A ride offered to a driver: enough to decide, not the rider's door
/// (the pickup is rounded to about a kilometre until they accept).
@immutable
class Offer {
  const Offer({
    required this.tripId,
    required this.expiresAt,
    required this.area,
    required this.pickupNear,
    required this.dropNear,
    required this.distanceM,
    required this.durationS,
    required this.fare,
    this.pickupDistanceM,
  });

  final int tripId;
  final DateTime expiresAt;
  final TaxiArea area;
  final GeoPoint pickupNear;
  final GeoPoint dropNear;
  final int? pickupDistanceM;
  final int distanceM;
  final int durationS;
  final Fare fare;

  factory Offer.fromJson(Map<String, dynamic> json) {
    GeoPoint point(Object? p) {
      final m = p! as Map<String, dynamic>;
      return GeoPoint((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
    }

    return Offer(
      tripId: json['tripId'] as int,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(json['expiresAt'] as int),
      area: TaxiArea.fromJson(json['area'] as Map<String, dynamic>),
      pickupNear: point(json['pickupNear']),
      dropNear: point(json['dropNear']),
      pickupDistanceM: json['pickupDistanceM'] as int?,
      distanceM: json['distanceM'] as int,
      durationS: json['durationS'] as int,
      fare: Fare.fromJson(json['fare'] as Map<String, dynamic>),
    );
  }
}

/// A driver's car, as riders see it.
@immutable
class Vehicle {
  const Vehicle({required this.vehicle, required this.plate});

  final String vehicle;
  final String plate;

  factory Vehicle.fromJson(Map<String, dynamic> json) =>
      Vehicle(vehicle: json['vehicle'] as String, plate: json['plate'] as String);
}

/// The compass direction from [from] to [to], in degrees (0 = north, 90 = east).
double bearing(GeoPoint from, GeoPoint to) {
  double rad(double d) => d * math.pi / 180;
  final dLng = rad(to.lng - from.lng);
  final y = math.sin(dLng) * math.cos(rad(to.lat));
  final x =
      math.cos(rad(from.lat)) * math.sin(rad(to.lat)) -
      math.sin(rad(from.lat)) * math.cos(rad(to.lat)) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// "17 min", "1 h 5 min".
String formatDuration(int seconds) {
  final minutes = (seconds / 60).ceil();
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${minutes % 60} min';
}
