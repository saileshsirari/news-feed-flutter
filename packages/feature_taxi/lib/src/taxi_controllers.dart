import 'dart:async';

import 'package:app_core/data/services/socket_provider.dart';
import 'package:app_core/session/current_user_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geo_kit/geo_kit.dart';
import 'package:payments_kit/payments_kit.dart';

import 'models.dart';
import 'taxi_api.dart';

/// One ride, kept live. Like a parcel-tracking page that updates itself:
/// it tunes in to the trip's channel on the app's socket, and
///
/// * "taxi_trip" (the status moved): fetches the trip again, since the
///   server decides what each person may see;
/// * "taxi_driver_location": moves the car on the map, no fetch;
/// * "reconnected": fetches again, in case something was missed.
///
/// Compose comparison: a ViewModel collecting a WebSocket Flow, filtered
/// by trip id, into a StateFlow the screen observes.
class TripController extends AsyncNotifier<Trip> {
  TripController(this.tripId);

  final int tripId;

  @override
  Future<Trip> build() async {
    final me = ref.read(currentUserProvider).requireValue!.id;
    final socket = ref.read(socketProvider(me));
    final stop = socket.watch({'type': 'watch_trip', 'tripId': tripId}, {'type': 'unwatch_trip', 'tripId': tripId});
    final live = socket.events.listen(_onEvent);
    ref.onDispose(() {
      live.cancel();
      stop();
    });
    return ref.read(taxiApiProvider).trip(tripId);
  }

  void _onEvent(Map<String, dynamic> event) {
    final current = state.value;
    switch (event['type']) {
      case 'taxi_trip' when event['tripId'] == tripId:
      case 'reconnected':
        unawaited(reload());
      case 'taxi_driver_location' when event['tripId'] == tripId && current != null && current.status.hasDriver:
        final p = GeoPoint((event['lat'] as num).toDouble(), (event['lng'] as num).toDouble());
        state = AsyncData(current.withDriverAt(p));
    }
  }

  Future<void> reload() async {
    try {
      final trip = await ref.read(taxiApiProvider).trip(tripId);
      if (ref.mounted) state = AsyncData(trip);
    } on Object catch (e) {
      debugPrint('[taxi] couldn\'t refresh ride $tripId: $e');
    }
  }

  /// Cancels the ride (riders before it starts, drivers before pickup).
  Future<void> cancel() async {
    final trip = await ref.read(taxiApiProvider).cancel(tripId);
    if (ref.mounted) state = AsyncData(trip);
  }

  /// Pays the fare online, the way tickets are paid: an order from the
  /// server, Razorpay's sheet, then the server checks the sheet's signed
  /// answer (the app never decides it paid). Returns what to tell the
  /// person when it didn't go through, or null.
  Future<String?> payOnline() async {
    final order = await ref.read(taxiApiProvider).pay(tripId);
    final options = order.checkoutOptions;
    if (options == null) {
      await reload();
      return 'This ride can\'t be paid online right now.';
    }
    final checkout = ref.read(checkoutProvider);
    final payments = ref.read(paymentsApiProvider);
    switch (await checkout.open(options)) {
      case final CheckoutPaid paid:
        await payments.confirm(order.id, paid);
        await reload();
        return null;
      case CheckoutCancelled():
        return null;
      case CheckoutFailed(:final message):
        return 'The payment didn\'t go through ($message). Nothing was charged.';
    }
  }

  /// Pays the driver in cash instead.
  Future<void> payInCash() async {
    final trip = await ref.read(taxiApiProvider).payInCash(tripId);
    if (ref.mounted) state = AsyncData(trip);
  }

  /// The driver's next move: "arrived", "start", "complete".
  Future<void> advance(String step) async {
    final trip = await ref.read(taxiApiProvider).advance(tripId, step);
    if (ref.mounted) state = AsyncData(trip);
  }
}

final tripProvider = AsyncNotifierProvider.autoDispose.family<TripController, Trip, int>(TripController.new);

/// The ride going now, as rider or driver (null: none). Asked when the
/// mini-app opens, so a ride survives closing the app.
final activeTripProvider = FutureProvider.autoDispose<Trip?>((ref) => ref.watch(taxiApiProvider).active());

/// Rides, newest first.
final tripHistoryProvider = FutureProvider.autoDispose<List<Trip>>((ref) => ref.watch(taxiApiProvider).history());

/// How often an on-duty driver sends their position (tests make it longer).
final driverPingIntervalProvider = Provider<Duration>((_) => const Duration(seconds: 4));

@immutable
class DriverState {
  const DriverState({
    this.vehicle,
    this.vehicleLoaded = false,
    this.online = false,
    this.goingOnline = false,
    this.areaName,
    this.offer,
    this.error,
  });

  final Vehicle? vehicle;

  /// False until the server said whether this person has a car set up.
  final bool vehicleLoaded;
  final bool online;
  final bool goingOnline;

  /// Where the driver is on duty ("Delhi NCR"), or null when outside every area.
  final String? areaName;
  final Offer? offer;
  final String? error;

  DriverState copyWith({
    Vehicle? vehicle,
    bool? vehicleLoaded,
    bool? online,
    bool? goingOnline,
    String? Function()? areaName,
    Offer? Function()? offer,
    String? Function()? error,
  }) => DriverState(
    vehicle: vehicle ?? this.vehicle,
    vehicleLoaded: vehicleLoaded ?? this.vehicleLoaded,
    online: online ?? this.online,
    goingOnline: goingOnline ?? this.goingOnline,
    areaName: areaName == null ? this.areaName : areaName(),
    offer: offer == null ? this.offer : offer(),
    error: error == null ? this.error : error(),
  );
}

/// Driver mode: on duty or not, the position pings, and the offer waiting.
///
/// While on duty it sends the phone's position every few seconds (only
/// while the app is open in phase 1; a background service is phase 2) and
/// listens for offers. Going off duty, or leaving the mini-app, stops both
/// and tells the server, which forgets the position.
class DriverController extends Notifier<DriverState> {
  Timer? _pings;

  /// Set while on duty: the API to say "off duty" with (even while this
  /// notifier is being disposed, when ref can't be used any more).
  TaxiApi? _onDutyApi;
  void Function()? _stopOffers;
  StreamSubscription<Map<String, dynamic>>? _events;

  @override
  DriverState build() {
    ref.onDispose(_stop);
    unawaited(_loadVehicle());
    return const DriverState();
  }

  TaxiApi get _api => ref.read(taxiApiProvider);

  Future<void> _loadVehicle() async {
    try {
      final vehicle = await _api.vehicle();
      if (ref.mounted) state = DriverState(vehicle: vehicle, vehicleLoaded: true);
    } on Object catch (e) {
      if (ref.mounted) state = state.copyWith(vehicleLoaded: true, error: () => taxiErrorText(e));
    }
  }

  Future<void> saveVehicle(String vehicle, String plate) async {
    try {
      final saved = await _api.saveVehicle(vehicle, plate);
      if (ref.mounted) state = state.copyWith(vehicle: saved, error: () => null);
    } on Object catch (e) {
      if (ref.mounted) state = state.copyWith(error: () => taxiErrorText(e));
    }
  }

  /// On duty: first position, then a ping every few seconds, and offers.
  Future<void> goOnline() async {
    if (state.online || state.goingOnline) return;
    state = state.copyWith(goingOnline: true, error: () => null);
    try {
      await _ping();
    } on LocationUnavailable catch (e) {
      if (ref.mounted) state = state.copyWith(goingOnline: false, error: () => e.message);
      return;
    } on Object catch (e) {
      if (ref.mounted) state = state.copyWith(goingOnline: false, error: () => taxiErrorText(e));
      return;
    }
    if (!ref.mounted) return;
    state = state.copyWith(online: true, goingOnline: false);
    _onDutyApi = _api;
    final me = ref.read(currentUserProvider).requireValue!.id;
    final socket = ref.read(socketProvider(me));
    _stopOffers = socket.watch({'type': 'watch_offers'}, {'type': 'unwatch_offers'});
    _events = socket.events.listen(_onEvent);
    _pings = Timer.periodic(ref.read(driverPingIntervalProvider), (_) {
      _ping().catchError((Object e) => debugPrint('[taxi] ping failed: $e')).ignore();
    });
    // An offer made while the socket was connecting.
    await _checkOffer();
  }

  Future<void> goOffline() async => _stop();

  void _stop() {
    _pings?.cancel();
    _pings = null;
    _stopOffers?.call();
    _stopOffers = null;
    _events?.cancel();
    _events = null;
    _onDutyApi?.offline().catchError((Object _) {}).ignore();
    _onDutyApi = null;
    if (ref.mounted) state = state.copyWith(online: false, areaName: () => null, offer: () => null);
  }

  Future<void> _ping() async {
    final here = await ref.read(driverLocationProvider).current();
    final answer = await _api.ping(here);
    if (!ref.mounted) return;
    state = state.copyWith(
      areaName: () => answer.areaName,
      error: () => answer.online ? null : 'You\'re outside every area taxi runs in, so you won\'t get rides here.',
    );
  }

  void _onEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'taxi_offer':
        state = state.copyWith(offer: () => Offer.fromJson(event['offer'] as Map<String, dynamic>));
      case 'taxi_offer_gone' when state.offer?.tripId == event['tripId']:
        state = state.copyWith(offer: () => null);
      case 'reconnected':
        unawaited(_checkOffer());
    }
  }

  Future<void> _checkOffer() async {
    try {
      final offer = await _api.offer();
      if (ref.mounted) state = state.copyWith(offer: () => offer);
    } on Object catch (e) {
      debugPrint('[taxi] couldn\'t check for offers: $e');
    }
  }

  /// Takes the offered ride; the trip's id, or null if it was gone.
  Future<int?> accept() async {
    final offer = state.offer;
    if (offer == null) return null;
    state = state.copyWith(offer: () => null);
    try {
      return (await _api.accept(offer.tripId)).id;
    } on Object catch (e) {
      if (ref.mounted) state = state.copyWith(error: () => taxiErrorText(e));
      return null;
    }
  }

  Future<void> decline() async {
    final offer = state.offer;
    if (offer == null) return;
    state = state.copyWith(offer: () => null);
    await _api.decline(offer.tripId).catchError((Object _) {});
  }

  /// The offer's time ran out on the phone (the server moves on by itself).
  void offerExpired(int tripId) {
    if (state.offer?.tripId == tripId) state = state.copyWith(offer: () => null);
  }
}

final driverProvider = NotifierProvider.autoDispose<DriverController, DriverState>(DriverController.new);
