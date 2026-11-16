import 'dart:async';

import 'package:app_core/app_core.dart' show NotificationChannel, cancelLocalNotification, showLocalNotification;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geo_kit/geo_kit.dart' show formatDistance;

import 'models.dart';

/// Gets the driver's attention while a ride offer waits, as Ola's and
/// Uber's driver apps do: a chime on repeat and the phone buzzing, until
/// they accept, decline, or the 15 seconds run out. Like a shop doorbell
/// that keeps ringing until someone comes to the counter.
///
/// It works with the app in the background too: on duty, Android keeps the
/// app running (the location foreground service), so the chime plays, and a
/// notification ("New ride · ₹396") brings the app back with one tap. With
/// the app closed altogether, there's no offer to ring for: the driver is
/// off duty.
abstract interface class OfferAlert {
  /// Starts ringing for [offer] (does nothing if it already is).
  Future<void> start(Offer offer);

  /// Stops it.
  Future<void> stop();
}

/// The real one: the chime from this package's assets, looped, a short
/// vibration every second (Flutter's haptics need no extra permission), and
/// a notification when the app isn't on screen.
class ChimeOfferAlert implements OfferAlert {
  /// One notification for ride requests: a new one replaces the last.
  static const _notificationId = 7001;
  static const _channel = NotificationChannel(
    id: 'taxi_ride_requests',
    name: 'Ride requests',
    description: 'A new ride request while you\'re on duty as a driver',
  );

  AudioPlayer? _player;
  Timer? _buzz;

  /// Package assets live under packages/feature_taxi/ in the app.
  static const _sound = 'packages/feature_taxi/assets/sounds/ride_request.wav';

  @override
  Future<void> start(Offer offer) async {
    if (_player != null) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      final away = offer.pickupDistanceM == null
          ? ''
          : ' · pickup ${formatDistance(offer.pickupDistanceM! / 1000)} away';
      unawaited(
        showLocalNotification(
          id: _notificationId,
          title: 'New ride · ${offer.fare}',
          body: 'Open Taxi to accept within 15 seconds$away.',
          channel: _channel,
        ).catchError((Object _) {}),
      );
    }
    final player = _player = AudioPlayer();
    _buzz = Timer.periodic(const Duration(seconds: 1), (_) => HapticFeedback.heavyImpact());
    unawaited(HapticFeedback.heavyImpact());
    try {
      // The full asset path is given, so the cache's own "assets/" prefix goes.
      player.audioCache.prefix = '';
      await player.setReleaseMode(ReleaseMode.loop);
      // Not "ducking" other audio: a driver may have music or a call on.
      await player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            usageType: AndroidUsageType.notificationRingtone,
            contentType: AndroidContentType.sonification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ),
      );
      await player.play(AssetSource(_sound), volume: 1);
    } on Object {
      // No sound (a browser that blocks it, a silent device): the buzz and
      // the card on screen are still there.
    }
  }

  @override
  Future<void> stop() async {
    unawaited(cancelLocalNotification(_notificationId));
    _buzz?.cancel();
    _buzz = null;
    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      await player.stop();
      await player.dispose();
    } on Object {
      // Already gone.
    }
  }
}

/// The driver's offer alert; tests swap in a fake that records start/stop.
final offerAlertProvider = Provider<OfferAlert>((ref) {
  final alert = ChimeOfferAlert();
  ref.onDispose(alert.stop);
  return alert;
});
