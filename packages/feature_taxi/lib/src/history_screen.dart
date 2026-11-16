import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'taxi_api.dart';
import 'taxi_controllers.dart';
import 'taxi_home_screen.dart';

/// Your rides, newest first, as Ola shows them: a card per ride with when,
/// where from and to, the car (or the rider, for rides you drove), the fare
/// and how it was paid. Rides you took and rides you drove sit on separate
/// tabs, shown only once you've done both. Tap one for its map and details.
///
/// (Pickups and drop-offs older than 30 days show only roughly: the server
/// rounds them away for privacy.)
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  /// Showing rides you drove (true) or took.
  bool _drove = false;

  @override
  Widget build(BuildContext context) {
    final trips = ref.watch(tripHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Your rides')),
      body: switch (trips) {
        AsyncData(value: final all) when all.isEmpty => const _Empty(),
        AsyncData(value: final all) => _list(all),
        AsyncError(:final error) => Center(child: Text(taxiErrorText(error))),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _list(List<Trip> all) {
    final took = all.where((t) => !t.isDriver).toList();
    final drove = all.where((t) => t.isDriver).toList();
    final both = took.isNotEmpty && drove.isNotEmpty;
    // Only one kind so far: show that, no tabs.
    final showDrove = both ? _drove : drove.isNotEmpty && took.isEmpty;
    final shown = showDrove ? drove : took;
    return RefreshIndicator(
      onRefresh: () => ref.refresh(tripHistoryProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          if (both)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, icon: const Icon(Icons.hail), label: Text('Rides (${took.length})')),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.local_taxi),
                    label: Text('Drives (${drove.length})'),
                  ),
                ],
                selected: {_drove},
                onSelectionChanged: (s) => setState(() => _drove = s.single),
              ),
            ),
          for (final trip in shown) _RideCard(trip: trip),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_taxi, size: 48),
          SizedBox(height: 12),
          Text('No rides yet. Your rides and the ones you drive show here.', textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

/// One ride, Ola-style:
///
///     Sun, 16 Nov · 11:50 AM                 Completed
///     ● Connaught Place
///     ┊
///     ● IGI Airport T3
///     ─────────────────────────────────────────────
///     White Swift Dzire · Ravi Kumar      ₹396 · Cash
class _RideCard extends ConsumerWidget {
  const _RideCard({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final when = DateFormat('EEE, d MMM · h:mm a').format(trip.requestedAt);
    final (status, statusColor) = switch (trip.status) {
      TripStatus.completed => ('Completed', colors.primary),
      TripStatus.cancelled when trip.cancelledBy == 'system' => ('No drivers', colors.error),
      TripStatus.cancelled => ('Cancelled', colors.error),
      _ => ('Going now', colors.tertiary),
    };
    final who = trip.isDriver
        ? 'Rider: ${trip.riderName ?? 'rider'}'
        : [trip.driver?.vehicle, trip.driver?.name].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final paid = switch (trip) {
      Trip(status: TripStatus.cancelled) => null,
      Trip(isPaidOnline: true) => 'Paid online',
      Trip(payment: PaymentMethod.online) => trip.status == TripStatus.completed ? 'Online · not paid' : 'Online',
      _ => 'Cash',
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openTrip(context, ref, trip.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(when, style: theme.textTheme.labelLarge)),
                  Text(status, style: theme.textTheme.labelLarge?.copyWith(color: statusColor)),
                ],
              ),
              const SizedBox(height: 10),
              _Stop(color: Colors.green.shade600, label: trip.pickupLabel),
              Padding(
                padding: const EdgeInsets.only(left: 4.5),
                child: Container(width: 1, height: 12, color: colors.outlineVariant),
              ),
              _Stop(color: Colors.red.shade600, label: trip.dropLabel),
              const Divider(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      who.isEmpty ? trip.area.name : who,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (trip.status != TripStatus.cancelled)
                    Text(trip.fare.toString(), style: theme.textTheme.titleSmall),
                  if (paid != null) Text(' · $paid', style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A coloured dot and a place: green for the pickup, red for the drop-off.
class _Stop extends StatelessWidget {
  const _Stop({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
    ],
  );
}
