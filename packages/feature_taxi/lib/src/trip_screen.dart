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

/// The map fills the screen; the ride's details sit on a sheet over it,
/// like Ola's and Uber's: drag the sheet down (or tap "Full map") to see
/// more map, and its handle and headline stay showing at the bottom, so
/// one tap or drag brings the details back.
///
///    ┌──────────────┐          ┌──────────────┐
///    │     map      │  drag ↓  │              │
///    │              │  ─────▶  │     map      │
///    ├──── ═══ ─────┤          │              │
///    │ Ravi is on…  │          ├──── ═══ ─────┤
///    │ details      │  ◀─────  │ Ravi is on…  │  (the peek)
///    └──────────────┘  tap/↑   └──────────────┘
///
/// Compose comparison: a BottomSheetScaffold with a peek height.
class _TripBody extends ConsumerStatefulWidget {
  const _TripBody({required this.trip});

  final Trip trip;

  @override
  ConsumerState<_TripBody> createState() => _TripBodyState();
}

class _TripBodyState extends ConsumerState<_TripBody> {
  final _sheet = DraggableScrollableController();

  /// The sheet's height pulled down: the handle and the headline.
  static const _peekPx = 88.0;

  /// Its usual height, as a share of the space under the app bar.
  static const _open = 0.5;

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  bool get _isPeeking => _sheet.isAttached && _sheet.size <= _peekFraction + 0.01;
  double _peekFraction = 0.12;

  /// Full map (sheet down to its peek), or the details back.
  void _toggle() {
    if (!_sheet.isAttached) return;
    _sheet.animateTo(
      _isPeeking ? _open : _peekFraction,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final car = trip.driverLocation;
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        _peekFraction = (_peekPx / box.maxHeight).clamp(0.05, _open - 0.05);
        return Stack(
          children: [
            Positioned.fill(
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
            Positioned(
              top: 12,
              right: 12,
              child: ListenableBuilder(
                listenable: _sheet,
                builder: (context, _) => FloatingActionButton.small(
                  heroTag: null,
                  tooltip: _isPeeking ? 'Show details' : 'Full map',
                  onPressed: _toggle,
                  child: Icon(_isPeeking ? Icons.fullscreen_exit : Icons.fullscreen),
                ),
              ),
            ),
            DraggableScrollableSheet(
              controller: _sheet,
              initialChildSize: _open,
              minChildSize: _peekFraction,
              maxChildSize: 0.85,
              snap: true,
              snapSizes: [_peekFraction, _open],
              builder: (context, scroll) => Material(
                elevation: 8,
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                clipBehavior: Clip.antiAlias,
                // Every line built (not lazily), so the actions are always there.
                child: SingleChildScrollView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The handle: drag it, or tap it to switch between map and details.
                        Semantics(
                          button: true,
                          label: 'Show or hide ride details',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _toggle,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Center(
                                child: Container(
                                  width: 36,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.outlineVariant,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        _TripPanel(trip: trip),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
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
        // First, on one line: it's what stays visible when the sheet is
        // pulled down to show the whole map.
        Text(headline, style: theme.textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (trip.status.isMatching) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
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
