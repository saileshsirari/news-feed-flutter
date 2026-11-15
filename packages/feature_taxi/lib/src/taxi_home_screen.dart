import 'package:app_core/geo/geo_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geo_kit/geo_kit.dart';

import 'driver_panel.dart';
import 'history_screen.dart';
import 'models.dart';
import 'taxi_api.dart';
import 'taxi_controllers.dart';
import 'trip_screen.dart';

/// Opens [tripId]'s screen; afterwards, asks again what's going on (the
/// ride may have finished while it was open).
Future<void> openTrip(BuildContext context, WidgetRef ref, int tripId) async {
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TripScreen(tripId: tripId)));
  ref.invalidate(activeTripProvider);
}

/// How a place is chosen: geo_kit's map picker (tests swap in their own).
typedef ChoosePlace = Future<Place?> Function(
  BuildContext context,
  WidgetRef ref, {
  required bool pickup,
  Place? initial,
  GeoPoint? near,
});

final choosePlaceProvider = Provider<ChoosePlace>(
  (_) =>
      (context, ref, {required pickup, initial, near}) => pickPlace(
        context,
        search: ref.read(placeSearchProvider),
        tiles: ref.read(mapTilesProvider),
        // Precise GPS, only when "My location" is tapped: a driver has to
        // find you, so a pickup rounded to ~1 km (as "near me" uses) won't
        // do. The exact spot still reaches only the driver who accepts.
        location: ref.read(pickupLocationProvider),
        // Less sure than this (approximate location allowed, weak GPS
        // indoors): ask the rider to drag the pin to the exact spot.
        approximateBeyondMetres: 150,
        initial: initial,
        near: near,
        title: pickup ? 'Pickup' : 'Drop-off',
      ),
);

/// Taxi's first screen: ask for a ride, or (switch at the top) drive.
class TaxiHomeScreen extends ConsumerStatefulWidget {
  const TaxiHomeScreen({super.key});

  @override
  ConsumerState<TaxiHomeScreen> createState() => _TaxiHomeScreenState();
}

enum _Mode { ride, drive }

class _TaxiHomeScreenState extends ConsumerState<TaxiHomeScreen> {
  _Mode _mode = _Mode.ride;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Taxi'),
        actions: [
          IconButton(
            tooltip: 'Your rides',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HistoryScreen())),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<_Mode>(
              segments: const [
                ButtonSegment(value: _Mode.ride, icon: Icon(Icons.hail), label: Text('Ride')),
                ButtonSegment(value: _Mode.drive, icon: Icon(Icons.local_taxi), label: Text('Drive')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.single),
            ),
          ),
        ),
      ),
      body: switch (_mode) {
        _Mode.ride => const _RidePanel(),
        _Mode.drive => const DriverPanel(),
      },
    );
  }
}

/// Where from, where to, how much; then "Request ride".
class _RidePanel extends ConsumerStatefulWidget {
  const _RidePanel();

  @override
  ConsumerState<_RidePanel> createState() => _RidePanelState();
}

class _RidePanelState extends ConsumerState<_RidePanel> {
  Place? _pickup;
  Place? _drop;
  Estimate? _estimate;
  PaymentMethod _payment = PaymentMethod.cash;
  String? _error;
  bool _busy = false;

  Future<void> _choose({required bool pickup}) async {
    final place = await ref.read(choosePlaceProvider)(
      context,
      ref,
      pickup: pickup,
      initial: pickup ? _pickup : _drop,
      near: (pickup ? _drop : _pickup)?.point,
    );
    if (place == null || !mounted) return;
    setState(() {
      if (pickup) {
        _pickup = place;
      } else {
        _drop = place;
      }
      _estimate = null;
      _error = null;
    });
    await _estimateFare();
  }

  Future<void> _estimateFare() async {
    final (pickup, drop) = (_pickup, _drop);
    if (pickup == null || drop == null) return;
    setState(() => _busy = true);
    try {
      final estimate = await ref.read(taxiApiProvider).estimate(pickup.point, drop.point);
      if (mounted) setState(() => _estimate = estimate);
    } on Object catch (e) {
      if (mounted) setState(() => _error = taxiErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request() async {
    setState(() => _busy = true);
    try {
      final payment = _estimate?.canPayOnline ?? false ? _payment : PaymentMethod.cash;
      final trip = await ref.read(taxiApiProvider).request(_pickup!, _drop!, payment: payment);
      if (!mounted) return;
      setState(() {
        _estimate = null;
        _drop = null;
      });
      await openTrip(context, ref, trip.id);
    } on Object catch (e) {
      if (mounted) setState(() => _error = taxiErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeTripProvider).value;
    final theme = Theme.of(context);
    final estimate = _estimate;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (active != null)
          Card(
            color: theme.colorScheme.primaryContainer,
            child: ListTile(
              leading: const Icon(Icons.local_taxi),
              title: Text(active.isDriver ? 'You\'re driving a ride' : 'You have a ride going'),
              subtitle: Text('${active.pickupLabel} → ${active.dropLabel}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openTrip(context, ref, active.id),
            ),
          ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.trip_origin),
                title: Text(_pickup?.name ?? 'Choose pickup'),
                subtitle: _pickup?.address == null
                    ? null
                    : Text(_pickup!.address!, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _choose(pickup: true),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.place),
                title: Text(_drop?.name ?? 'Where to?'),
                subtitle: _drop?.address == null
                    ? null
                    : Text(_drop!.address!, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _choose(pickup: false),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        if (estimate != null && !_busy) ...[
          Text(estimate.fare.toString(), style: theme.textTheme.displaySmall),
          Text(
            '${formatDistance(estimate.distanceM / 1000)} · about ${formatDuration(estimate.durationS)} · ${estimate.area.name}',
          ),
          const SizedBox(height: 4),
          Text(
            estimate.routing == 'straight-line'
                ? 'A rough estimate from the distance; this is the price you pay.'
                : 'This is the price you pay.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          // How to pay: cash always; online (Razorpay: UPI, card) where it's set up.
          if (estimate.canPayOnline)
            SegmentedButton<PaymentMethod>(
              segments: const [
                ButtonSegment(value: PaymentMethod.cash, icon: Icon(Icons.payments_outlined), label: Text('Cash')),
                ButtonSegment(value: PaymentMethod.online, icon: Icon(Icons.qr_code), label: Text('UPI / card')),
              ],
              selected: {_payment},
              onSelectionChanged: (s) => setState(() => _payment = s.single),
            )
          else
            Text('Pay in cash to your driver.', style: theme.textTheme.bodyMedium),
          if (estimate.canPayOnline && _payment == PaymentMethod.online)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('You pay after the ride, in the app.', style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: active != null ? null : _request,
            icon: const Icon(Icons.hail),
            label: Text('Request ride · ${estimate.fare}'),
          ),
        ],
        if (_pickup == null || _drop == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Your exact pickup is shared only with the driver who takes your ride.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
