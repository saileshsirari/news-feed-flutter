import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Gets the driver's attention while a ride offer waits, as Ola's and
/// Uber's driver apps do: a chime on repeat and the phone buzzing, until
/// they accept, decline, or the 15 seconds run out. Like a shop doorbell
/// that keeps ringing until someone comes to the counter.
///
/// Only while the app is open (phase 1). With the app in the background,
/// a driver would need a push notification with a sound: phase 2.
abstract interface class OfferAlert {
  /// Starts ringing (does nothing if it already is).
  Future<void> start();

  /// Stops it.
  Future<void> stop();
}

/// The real one: the chime from this package's assets, looped, and a short
/// vibration every second (Flutter's haptics need no extra permission).
class ChimeOfferAlert implements OfferAlert {
  AudioPlayer? _player;
  Timer? _buzz;

  /// Package assets live under packages/feature_taxi/ in the app.
  static const _sound = 'packages/feature_taxi/assets/sounds/ride_request.wav';

  @override
  Future<void> start() async {
    if (_player != null) return;
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
