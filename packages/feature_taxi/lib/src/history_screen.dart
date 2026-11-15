import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'taxi_api.dart';
import 'taxi_controllers.dart';
import 'taxi_home_screen.dart';

/// Your rides, as rider and as driver, newest first. (Pickups and drop-offs
/// older than 30 days show only roughly: the server rounds them away.)
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(tripHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Your rides')),
      body: switch (trips) {
        AsyncData(value: final list) when list.isEmpty => const Center(child: Text('No rides yet.')),
        AsyncData(value: final list) => RefreshIndicator(
          onRefresh: () => ref.refresh(tripHistoryProvider.future),
          child: ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => _TripTile(trip: list[i]),
          ),
        ),
        AsyncError(:final error) => Center(child: Text(taxiErrorText(error))),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _TripTile extends ConsumerWidget {
  const _TripTile({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final when = DateFormat.yMMMd().add_jm().format(trip.requestedAt);
    final status = switch (trip.status) {
      TripStatus.completed => trip.fare.toString(),
      TripStatus.cancelled => trip.cancelledBy == 'system' ? 'No drivers' : 'Cancelled',
      _ => 'Going now',
    };
    return ListTile(
      leading: Icon(trip.isDriver ? Icons.local_taxi : Icons.hail),
      title: Text('${trip.pickupLabel} → ${trip.dropLabel}', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('$when · ${trip.area.name}${trip.isDriver ? ' · as driver' : ''}'),
      trailing: Text(status),
      onTap: () => openTrip(context, ref, trip.id),
    );
  }
}
