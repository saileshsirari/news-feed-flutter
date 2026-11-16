import 'dart:async';
import 'dart:convert';

import 'package:app_core/data/services/socket_provider.dart';
import 'package:app_core/session/current_user_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geo_kit/geo_kit.dart';

import '../chat/conversation_notifier.dart';
import '../e2e/e2e_chats.dart';
import 'chat_location.dart';
import 'live_location_api.dart';
import 'live_sealing.dart';

/// Where I am, precisely (GPS), asked only when I tap "Send your current
/// location" or start a live share. The rest of the app keeps its ~1 km
/// location; a shared location is meant to be exact.
final chatPreciseLocationProvider = Provider<AccurateLocationSource>(
  (_) => const DeviceLocation(decimals: 5, precise: true),
);

/// My position as I move, while a live share runs (an Android foreground
/// service with a "Sharing live location" notification, so it keeps going
/// with the screen off).
final chatTrackerProvider = Provider<LocationTracker>((_) => const DeviceLocationTracker());

/// How often a live share sends my position (tests make it zero).
final liveUpdateIntervalProvider = Provider<Duration>((_) => const Duration(seconds: 10));

/// Opens directions in the phone's maps app (tests swap it).
final chatLinkLauncherProvider = Provider<LinkLauncher>((_) => launchExternally);

/// The live share choices, as WhatsApp offers them.
const liveShareLengths = [Duration(minutes: 15), Duration(hours: 1), Duration(hours: 8)];

/// One live share of mine that's running.
@immutable
class OutgoingShare {
  const OutgoingShare({required this.conversationId, required this.messageId, required this.until, this.key});

  final int conversationId;

  /// The chat message that started it (its id names the share).
  final int messageId;
  final DateTime until;

  /// Encrypted chats: what my positions are sealed with (see LiveUpdateSealer).
  final List<int>? key;

  bool get isE2e => key != null;
}

/// My live shares, by chat: start one, send my position as I move, stop it
/// (or let it run out). Lives as long as I'm signed in, not just while the
/// chat is open: a share keeps going when I leave the chat, like WhatsApp's.
///
/// Compose/Android comparison: an app-scoped repository driving a
/// location foreground service.
class LiveShareController extends Notifier<Map<int, OutgoingShare>> {
  StreamSubscription<GeoPoint>? _tracking;
  final _timers = <int, Timer>{};
  final _sealer = LiveUpdateSealer();
  DateTime? _lastSent;

  @override
  Map<int, OutgoingShare> build() {
    ref.onDispose(() {
      _tracking?.cancel();
      for (final t in _timers.values) {
        t.cancel();
      }
    });
    return const {};
  }

  /// Starts sharing my live location in [conversationId] for [length]:
  /// the start message (with where I am now), then my position as I move.
  /// Returns why it couldn't start, or null.
  Future<String?> start(int conversationId, Duration length, {required bool isE2e}) async {
    if (state.containsKey(conversationId)) return null;
    final GeoPoint here;
    try {
      here = (await ref.read(chatPreciseLocationProvider).currentWithAccuracy()).point;
    } on LocationUnavailable catch (e) {
      return e.message;
    }
    final until = DateTime.now().add(length);
    final key = isE2e ? LiveUpdateSealer.newKey() : null;
    final sent = await ref.read(conversationProvider(conversationId).notifier).sendLocation({
      'lat': here.lat,
      'lng': here.lng,
      // A normal chat: the server sets the end. An encrypted one: it
      // can't read this, so the message itself says, with the key.
      if (!isE2e) 'liveMinutes': length.inMinutes,
      if (isE2e) 'live': {'until': until.millisecondsSinceEpoch, 'key': base64Encode(key!), 'stoppedAt': null},
    });
    if (sent == null) return 'Couldn\'t start sharing. Check your connection.';
    final serverUntil = ChatLocation.of(sent)?.liveUntil;
    final share = OutgoingShare(
      conversationId: conversationId,
      messageId: sent.id,
      until: serverUntil ?? until,
      key: key,
    );
    state = {...state, conversationId: share};
    _timers[conversationId] = Timer(share.until.difference(DateTime.now()), () => _end(conversationId));
    _track();
    return null;
  }

  /// Stops sharing in [conversationId] now: everyone's map loses my dot.
  Future<void> stop(int conversationId) async {
    final share = state[conversationId];
    if (share == null) return;
    _end(conversationId);
    try {
      if (share.isE2e) {
        final me = ref.read(currentUserProvider).requireValue!.id;
        await ref
            .read(e2eChatsProvider(me))
            .sendLocationStop(conversationId, share.messageId, clientMessageId: 'stop-${share.messageId}');
      } else {
        await ref.read(liveLocationApiProvider).stop(conversationId, share.messageId);
      }
    } on Object catch (e) {
      debugPrint('[location] couldn\'t tell the chat the share stopped: $e');
    }
  }

  void _end(int conversationId) {
    _timers.remove(conversationId)?.cancel();
    if (!ref.mounted) return;
    state = {...state}..remove(conversationId);
    if (state.isEmpty) {
      _tracking?.cancel(); // and its notification
      _tracking = null;
      _lastSent = null;
    }
  }

  /// GPS while any share runs; each position goes to every running share.
  void _track() {
    if (_tracking != null) return;
    final every = ref.read(liveUpdateIntervalProvider);
    _tracking = ref
        .read(chatTrackerProvider)
        .track(
          every: every,
          notificationTitle: 'Sharing live location',
          notificationText: 'People in your chat can see where you are. Stop in the chat.',
        )
        .listen((here) {
          final last = _lastSent;
          if (last != null && DateTime.now().difference(last) < every * 0.8) return;
          _lastSent = DateTime.now();
          for (final share in state.values) {
            _send(share, here).catchError((Object e) => debugPrint('[location] update failed: $e')).ignore();
          }
        }, onError: (Object e) => debugPrint('[location] tracking stopped: $e'));
  }

  Future<void> _send(OutgoingShare share, GeoPoint here) async {
    if (!share.isE2e) {
      await ref.read(liveLocationApiProvider).update(share.conversationId, share.messageId, here);
      return;
    }
    final me = ref.read(currentUserProvider).requireValue!.id;
    final sealed = await _sealer.seal(share.key!, {
      'shareId': share.messageId,
      'lat': here.lat,
      'lng': here.lng,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    final deviceId = await ref.read(e2eChatsProvider(me)).currentDeviceId();
    await ref.read(liveLocationApiProvider).signal(share.conversationId, deviceId: deviceId, sealed: sealed);
  }
}

final liveShareProvider = NotifierProvider<LiveShareController, Map<int, OutgoingShare>>(LiveShareController.new);

/// What one chat's map knows about its live shares.
@immutable
class LiveView {
  const LiveView({this.points = const {}, this.stopped = const {}});

  /// The latest position of each running share, by its start message's id.
  final Map<int, LivePoint> points;

  /// Shares heard to have stopped early since the chat opened.
  final Set<int> stopped;

  LiveView copyWith({Map<int, LivePoint>? points, Set<int>? stopped}) =>
      LiveView(points: points ?? this.points, stopped: stopped ?? this.stopped);
}

/// The live dots in one open chat: positions as they arrive on the socket
/// (normal chats: in the clear; encrypted chats: sealed, opened here with
/// the key from the share's start message), and the latest ones from the
/// server when the chat opens.
class LiveViewNotifier extends Notifier<LiveView> {
  LiveViewNotifier(this.conversationId);

  final int conversationId;
  final _sealer = LiveUpdateSealer();

  @override
  LiveView build() {
    final me = ref.read(currentUserProvider).requireValue!.id;
    final socket = ref.watch(socketProvider(me));
    final sub = socket.events.listen(_onEvent);
    ref.onDispose(sub.cancel);
    unawaited(_loadCurrent());
    return const LiveView();
  }

  Future<void> _loadCurrent() async {
    try {
      final points = await ref.read(liveLocationApiProvider).current(conversationId);
      if (!ref.mounted) return;
      state = state.copyWith(points: {...state.points, for (final p in points) p.messageId: p});
    } on Object {
      // An encrypted chat (the server knows nothing to tell), or offline:
      // positions arrive live anyway.
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    if (event['conversationId'] != conversationId) return;
    switch (event['type']) {
      case 'live_location':
        final point = LivePoint(
          messageId: event['messageId'] as int,
          senderId: event['senderId'] as int,
          point: GeoPoint((event['lat'] as num).toDouble(), (event['lng'] as num).toDouble()),
          at: DateTime.fromMillisecondsSinceEpoch(event['at'] as int),
        );
        state = state.copyWith(points: {...state.points, point.messageId: point});
      case 'live_location_stopped':
        final id = event['messageId'] as int;
        state = state.copyWith(points: {...state.points}..remove(id), stopped: {...state.stopped, id});
      case 'live_signal':
        unawaited(_openSealed(event['senderId'] as int, event['ciphertext'] as String));
    }
  }

  /// A sealed position: tried with the keys of that sender's live shares in
  /// this chat (usually one), from their decrypted start messages.
  Future<void> _openSealed(int senderId, String sealed) async {
    final messages = ref.read(conversationProvider(conversationId)).messages;
    for (final message in messages.reversed) {
      if (message.senderId != senderId) continue;
      final key = ChatLocation.of(message)?.liveKey;
      if (key == null) continue;
      final update = await _sealer.open(key, sealed);
      if (update == null || update['shareId'] != message.id) continue;
      if (!ref.mounted) return;
      final point = LivePoint(
        messageId: message.id,
        senderId: senderId,
        point: GeoPoint((update['lat'] as num).toDouble(), (update['lng'] as num).toDouble()),
        at: DateTime.fromMillisecondsSinceEpoch(update['at'] as int),
      );
      state = state.copyWith(points: {...state.points, point.messageId: point});
      return;
    }
  }
}

final liveViewProvider = NotifierProvider.autoDispose.family<LiveViewNotifier, LiveView, int>(LiveViewNotifier.new);
