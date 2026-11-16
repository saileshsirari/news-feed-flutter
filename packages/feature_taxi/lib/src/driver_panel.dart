import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geo_kit/geo_kit.dart';

import 'models.dart';
import 'taxi_controllers.dart';
import 'taxi_home_screen.dart';

/// Driver mode: your car, an on-duty switch, and offers as they come.
class DriverPanel extends ConsumerWidget {
  const DriverPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final driver = ref.watch(driverProvider);
    final controller = ref.read(driverProvider.notifier);
    final active = ref.watch(activeTripProvider).value;
    final theme = Theme.of(context);
    if (!driver.vehicleLoaded) return const Center(child: CircularProgressIndicator());

    final offer = driver.offer;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (driver.vehicle == null)
          _VehicleForm(onSave: controller.saveVehicle)
        else ...[
          ListTile(
            leading: const Icon(Icons.directions_car),
            title: Text(driver.vehicle!.vehicle),
            subtitle: Text(driver.vehicle!.plate),
          ),
          SwitchListTile(
            title: const Text('On duty'),
            subtitle: Text(
              driver.goingOnline
                  ? 'Finding where you are…'
                  : driver.online
                  ? (driver.areaName == null ? 'Outside every service area' : 'Taking rides in ${driver.areaName}')
                  : 'Your position is shared only while you\'re on duty.',
            ),
            value: driver.online,
            onChanged: driver.goingOnline ? null : (on) => on ? controller.goOnline() : controller.goOffline(),
          ),
        ],
        if (driver.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(driver.error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        if (active != null && active.isDriver)
          Card(
            color: theme.colorScheme.primaryContainer,
            child: ListTile(
              leading: const Icon(Icons.local_taxi),
              title: const Text('Continue your ride'),
              subtitle: Text('${active.pickupLabel} → ${active.dropLabel}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openTrip(context, ref, active.id),
            ),
          ),
        if (offer != null)
          _OfferCard(
            key: ValueKey(offer.tripId),
            offer: offer,
            onAccept: () async {
              final tripId = await controller.accept();
              if (tripId != null && context.mounted) await openTrip(context, ref, tripId);
            },
            onDecline: controller.decline,
            onExpired: () => controller.offerExpired(offer.tripId),
          )
        else if (driver.online && active == null)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(child: Text('Waiting for a ride request…')),
          ),
        const SizedBox(height: 16),
        Text('Keep the app open while on duty (phase 1). Rides are paid in cash.', style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _VehicleForm extends StatefulWidget {
  const _VehicleForm({required this.onSave});

  final Future<void> Function(String vehicle, String plate) onSave;

  @override
  State<_VehicleForm> createState() => _VehicleFormState();
}

class _VehicleFormState extends State<_VehicleForm> {
  final _vehicle = TextEditingController();
  final _plate = TextEditingController();

  @override
  void dispose() {
    _vehicle.dispose();
    _plate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Your car', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('Riders see this, so they can spot you.'),
        TextField(
          controller: _vehicle,
          decoration: const InputDecoration(labelText: 'Car (colour and model)', hintText: 'White Swift Dzire'),
        ),
        TextField(
          controller: _plate,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Number plate', hintText: 'DL 1C AB 1234'),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: () => widget.onSave(_vehicle.text, _plate.text), child: const Text('Save')),
      ],
    );
  }
}

/// A ride offer with a countdown: accept within 15 seconds, or it goes to
/// the next driver.
class _OfferCard extends StatefulWidget {
  const _OfferCard({
    super.key,
    required this.offer,
    required this.onAccept,
    required this.onDecline,
    required this.onExpired,
  });

  final Offer offer;

  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onExpired;

  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard> {
  /// What the phone's clock says the offer's 15 s are, from when it
  /// arrived: the server's expiry, but the phone's own clock may be off by
  /// minutes, so only the length is trusted.
  late final DateTime _until;
  late final Duration _window;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final left = widget.offer.expiresAt.difference(now);
    // A wrong phone clock: assume the usual 15 s.
    _window = left.isNegative || left > const Duration(seconds: 30) ? const Duration(seconds: 15) : left;
    _until = now.add(_window);
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (DateTime.now().isAfter(_until)) {
        _tick?.cancel();
        widget.onExpired();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final left = _until.difference(DateTime.now());
    final seconds = left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil();
    final theme = Theme.of(context);
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('New ride · ${offer.fare}', style: theme.textTheme.titleLarge)),
                Text('${seconds}s', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _window.inMilliseconds == 0
                  ? 0
                  : left.inMilliseconds.clamp(0, _window.inMilliseconds) / _window.inMilliseconds,
            ),
            const SizedBox(height: 8),
            if (offer.pickupDistanceM != null) Text('Pickup ${formatDistance(offer.pickupDistanceM! / 1000)} from you'),
            Text('Ride ${formatDistance(offer.distanceM / 1000)} · about ${formatDuration(offer.durationS)} · cash'),
            Text('The exact pickup shows once you accept.', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: widget.onDecline, child: const Text('Decline')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(onPressed: widget.onAccept, child: const Text('Accept')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
