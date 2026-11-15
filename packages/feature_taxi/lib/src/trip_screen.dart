import 'package:app_core/geo/geo_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geo_kit/geo_kit.dart';

import 'models.dart';
import 'taxi_api.dart';
import 'taxi_controllers.dart';

/// One ride, live: the map (pickup, drop-off, and the car once a driver
/// has it), where things stand, and the next step. The rider and the
/// driver see the same screen; only the driver gets the buttons that move
/// the ride along (arrived, start, complete).
class TripScreen extends ConsumerWidget {
  const TripScreen({super.key, required this.tripId});

  final int tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripProvider(tripId));
    return Scaffold(
      appBar: AppBar(title: Text(trip.value?.isDriver ?? false ? 'Your ride (driving)' : 'Your ride')),
      body: switch (trip) {
        AsyncData(:final value) => _TripBody(trip: value),
        AsyncError(:final error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(taxiErrorText(error), textAlign: TextAlign.center),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _TripBody extends ConsumerWidget {
  const _TripBody({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final car = trip.driverLocation;
    return Column(
      children: [
        Expanded(
          child: PlaceMap(
            // A new key when the car first appears, so the map opens on it.
            key: ValueKey(car == null),
            tiles: ref.watch(mapTilesProvider),
            center: car ?? trip.pickup,
            zoom: 14,
            pins: [
              MapPin(point: trip.pickup, label: 'Pickup: ${trip.pickupLabel}'),
              MapPin(point: trip.drop, label: 'Drop-off: ${trip.dropLabel}'),
              if (car != null) MapPin(point: car, label: trip.isDriver ? 'You' : 'Your driver', highlighted: true),
            ],
          ),
        ),
        Material(
          elevation: 8,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _TripPanel(trip: trip),
            ),
          ),
        ),
      ],
    );
  }
}

class _TripPanel extends ConsumerStatefulWidget {
  const _TripPanel({required this.trip});

  final Trip trip;

  @override
  ConsumerState<_TripPanel> createState() => _TripPanelState();
}

class _TripPanelState extends ConsumerState<_TripPanel> {
  bool _busy = false;

  Future<void> _do(Future<void> Function(TripController c) action) async {
    setState(() => _busy = true);
    try {
      await action(ref.read(tripProvider(widget.trip.id).notifier));
    } on Object catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(taxiErrorText(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this ride?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel ride')),
        ],
      ),
    );
    if (sure == true) await _do((c) => c.cancel());
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final theme = Theme.of(context);
    final (headline, detail) = _words(trip);
    final driver = trip.driver;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (trip.status.isMatching) const LinearProgressIndicator(),
        if (trip.status.isMatching) const SizedBox(height: 12),
        Text(headline, style: theme.textTheme.titleLarge),
        if (detail != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(detail)),
        if (driver != null && !trip.isDriver && !trip.status.isOver)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.local_taxi)),
            title: Text(driver.name),
            subtitle: Text([driver.vehicle, driver.plate].where((s) => s.isNotEmpty).join(' · ')),
          ),
        const SizedBox(height: 8),
        Text('${trip.pickupLabel}  →  ${trip.dropLabel}', style: theme.textTheme.bodyMedium),
        Text(
          '${formatDistance(trip.distanceM / 1000)} · ${formatDuration(trip.durationS)} · ${trip.fare} · Cash',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        ..._actions(trip),
      ],
    );
  }

  /// What to say: a headline and a line under it.
  (String, String?) _words(Trip trip) {
    final eta = trip.pickupEtaS == null ? null : 'About ${formatDuration(trip.pickupEtaS!)} away.';
    if (trip.isDriver) {
      return switch (trip.status) {
        TripStatus.accepted => (
          'Drive to the pickup',
          'Picking up ${trip.riderName ?? 'your rider'} at ${trip.pickupLabel}.',
        ),
        TripStatus.arriving => ('Waiting for ${trip.riderName ?? 'your rider'}', 'Start the ride once they\'re in.'),
        TripStatus.inProgress => ('On the way to ${trip.dropLabel}', null),
        TripStatus.completed => ('Ride complete', 'Collect ${trip.fare} in cash.'),
        TripStatus.cancelled => ('Ride cancelled', trip.cancelReason),
        _ => ('Ride offered', null),
      };
    }
    return switch (trip.status) {
      TripStatus.requested ||
      TripStatus.offered => ('Finding you a driver…', 'Asking the nearest drivers, one at a time.'),
      TripStatus.accepted => ('${trip.driver?.name ?? 'Your driver'} is on the way', eta),
      TripStatus.arriving => ('Your driver is here', 'Look for ${trip.driver?.plate ?? 'your car'}.'),
      TripStatus.inProgress => ('On the way to ${trip.dropLabel}', null),
      TripStatus.completed => ('You\'ve arrived', 'Please pay ${trip.fare} in cash.'),
      TripStatus.cancelled => switch (trip.cancelledBy) {
        'system' => ('No drivers nearby', 'Nobody could take this ride. Try again in a few minutes.'),
        'driver' => ('Your driver cancelled', 'Sorry about that. You can ask for another ride.'),
        _ => ('Ride cancelled', null),
      },
    };
  }

  List<Widget> _actions(Trip trip) {
    final cancel = OutlinedButton(onPressed: _busy ? null : _cancel, child: const Text('Cancel ride'));
    if (trip.isDriver) {
      final next = switch (trip.status) {
        TripStatus.accepted => ('arrived', 'I\'ve arrived'),
        TripStatus.arriving => ('start', 'Start ride'),
        TripStatus.inProgress => ('complete', 'Complete ride'),
        _ => null,
      };
      return [
        if (next != null)
          FilledButton(onPressed: _busy ? null : () => _do((c) => c.advance(next.$1)), child: Text(next.$2)),
        if (trip.status == TripStatus.accepted || trip.status == TripStatus.arriving) ...[
          const SizedBox(height: 8),
          cancel,
        ],
        if (trip.status.isOver) FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ];
    }
    return [
      if (!trip.status.isOver && trip.status != TripStatus.inProgress) cancel,
      if (trip.status.isOver) FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
    ];
  }
}
