import 'dart:async';

import 'package:app_core/geo/geo_services.dart';
import 'package:app_core/models/models.dart';
import 'package:app_core/session/current_user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geo_kit/geo_kit.dart';

import '../chat/conversation_notifier.dart';
import 'chat_location.dart';
import 'live_location_api.dart';
import 'location_sharing.dart';

/// Is the live share started by [message] over, as far as this chat knows?
bool liveShareEnded(ChatMessage message, ChatLocation location, LiveView view, List<ChatMessage> messages) =>
    !location.runningAt(DateTime.now()) ||
    view.stopped.contains(message.id) ||
    messages.any((m) => ChatLocation.stopOf(m) == message.id);

/// A person's dot on the map: a filled circle with a white ring, as in
/// WhatsApp's live location.
Widget personDot(BuildContext context, {bool faded = false}) {
  final colors = Theme.of(context).colorScheme;
  return Container(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: faded ? colors.outline : colors.primary,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
    ),
    child: const Icon(Icons.person, color: Colors.white, size: 18),
  );
}

/// A location message in the chat: a small map and what it is. Tapping
/// opens the full map, with directions.
class ChatLocationBubble extends ConsumerWidget {
  const ChatLocationBubble({super.key, required this.message, required this.location});

  final ChatMessage message;
  final ChatLocation location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final view = location.isLive ? ref.watch(liveViewProvider(message.conversationId)) : const LiveView();
    final messages = ref.watch(conversationProvider(message.conversationId).select((s) => s.messages));
    final ended = location.isLive && liveShareEnded(message, location, view, messages);
    final live = view.points[message.id];
    final at = ended || live == null ? location.point : live.point;
    final String detail;
    if (!location.isLive) {
      detail = location.address ?? '${location.point.lat.toStringAsFixed(5)}, ${location.point.lng.toStringAsFixed(5)}';
    } else if (ended) {
      detail = 'Live location ended';
    } else {
      final left = timeLeft(location.liveUntil!.difference(DateTime.now()));
      detail = live == null ? 'Live · $left' : 'Live · updated ${_ago(live.at)} · $left';
    }
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LocationScreen(conversationId: message.conversationId, messageId: message.id),
        ),
      ),
      child: SizedBox(
        width: 230,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 130,
                // A still picture: taps open the full map instead.
                child: IgnorePointer(
                  child: PlaceMap(
                    key: ValueKey('${at.lat},${at.lng}'),
                    tiles: ref.watch(mapTilesProvider),
                    center: at,
                    zoom: 15,
                    interactive: false,
                    pins: [
                      if (location.isLive)
                        MapPin(
                          point: at,
                          label: location.title,
                          marker: personDot(context, faded: ended),
                          markerSize: 30,
                        )
                      else
                        MapPin(point: at, label: location.title),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  location.isLive ? Icons.my_location : Icons.location_on,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(location.title, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            Text(detail, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// "just now", "2 min ago".
String _ago(DateTime at) {
  final s = DateTime.now().difference(at).inSeconds;
  if (s < 60) return 'just now';
  return '${(s / 60).floor()} min ago';
}

/// A shared location full screen: the map (the dot moving, for a live
/// share), and directions in the phone's maps app.
class LocationScreen extends ConsumerStatefulWidget {
  const LocationScreen({super.key, required this.conversationId, required this.messageId});

  final int conversationId;
  final int messageId;

  @override
  ConsumerState<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends ConsumerState<LocationScreen> {
  /// Redraws "updated 1 min ago" and the time left.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _directions(GeoPoint to) async {
    final opened = await openDirections(ref.read(chatLinkLauncherProvider), to, platform: Theme.of(context).platform);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Couldn\'t open a maps app on this device.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(conversationProvider(widget.conversationId).select((s) => s.messages));
    final message = messages.where((m) => m.id == widget.messageId).firstOrNull;
    final location = message == null ? null : ChatLocation.of(message);
    if (message == null || location == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This location isn\'t available.')),
      );
    }
    final me = ref.watch(currentUserProvider).requireValue!.id;
    final view = ref.watch(liveViewProvider(widget.conversationId));
    final mine = message.senderId == me;
    final ended = location.isLive && liveShareEnded(message, location, view, messages);
    final LivePoint? live = ended ? null : view.points[message.id];
    final at = live?.point ?? location.point;
    final theme = Theme.of(context);
    final who = mine ? 'You' : '@${message.senderUsername}';
    return Scaffold(
      appBar: AppBar(title: Text(location.isLive ? '$who · live location' : location.title)),
      body: Column(
        children: [
          Expanded(
            child: PlaceMap(
              key: ValueKey(live == null),
              tiles: ref.watch(mapTilesProvider),
              center: at,
              zoom: 16,
              pins: [
                if (location.isLive)
                  MapPin(
                    point: at,
                    label: who,
                    marker: personDot(context, faded: ended),
                    markerSize: 36,
                  )
                else
                  MapPin(point: at, label: location.title),
              ],
            ),
          ),
          Material(
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(location.title, style: theme.textTheme.titleMedium),
                    if (location.address != null) Text(location.address!),
                    if (location.isLive)
                      Text(
                        ended
                            ? 'Live location ended. This is where it started.'
                            : live == null
                            ? 'Waiting for the first update… ${timeLeft(location.liveUntil!.difference(DateTime.now()))}'
                            : 'Updated ${_ago(live.at)} · ${timeLeft(location.liveUntil!.difference(DateTime.now()))}',
                        style: theme.textTheme.bodySmall,
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _directions(at),
                      icon: const Icon(Icons.directions),
                      label: const Text('Directions'),
                    ),
                    if (mine && location.isLive && !ended) ...[
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => ref.read(liveShareProvider.notifier).stop(widget.conversationId),
                        child: const Text('Stop sharing'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What 📍 in the composer offers: your current location, live location,
/// or any place on the map.
Future<void> showShareLocationSheet(
  BuildContext context,
  WidgetRef ref, {
  required int conversationId,
  required bool isE2e,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.my_location),
            title: const Text('Send your current location'),
            subtitle: const Text('Exact, from GPS, once'),
            onTap: () async {
              Navigator.pop(sheet);
              await _sendCurrent(context, ref, conversationId);
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_location),
            title: const Text('Share live location'),
            subtitle: const Text('Your dot moves for everyone here, until it runs out or you stop'),
            onTap: () async {
              Navigator.pop(sheet);
              await _chooseLiveLength(context, ref, conversationId, isE2e: isE2e);
            },
          ),
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: const Text('Choose a place'),
            subtitle: const Text('Search, or move the map under the pin'),
            onTap: () async {
              Navigator.pop(sheet);
              final place = await pickPlace(
                context,
                search: ref.read(placeSearchProvider),
                tiles: ref.read(mapTilesProvider),
                location: ref.read(chatPreciseLocationProvider),
                approximateBeyondMetres: 150,
                title: 'Share a place',
              );
              if (place == null) return;
              await ref.read(conversationProvider(conversationId).notifier).sendLocation({
                'lat': place.point.lat,
                'lng': place.point.lng,
                'name': place.name,
                'address': ?place.address,
              });
            },
          ),
          if (isE2e)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('🔒 End-to-end encrypted: the server can\'t see where you are.', textAlign: TextAlign.center),
            ),
        ],
      ),
    ),
  );
}

Future<void> _sendCurrent(BuildContext context, WidgetRef ref, int conversationId) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final here = await ref.read(chatPreciseLocationProvider).currentWithAccuracy();
    await ref.read(conversationProvider(conversationId).notifier).sendLocation({
      'lat': here.point.lat,
      'lng': here.point.lng,
      'name': 'My location',
      if (here.accuracyMetres > 150) 'address': 'Approximate (within about ${here.accuracyMetres.round()} m)',
    });
  } on LocationUnavailable catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

Future<void> _chooseLiveLength(BuildContext context, WidgetRef ref, int conversationId, {required bool isE2e}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final length = await showDialog<Duration>(
    context: context,
    builder: (dialog) => SimpleDialog(
      title: const Text('Share live location for'),
      children: [
        for (final d in liveShareLengths)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialog, d),
            child: Text(
              d.inMinutes < 60
                  ? '${d.inMinutes} minutes'
                  : d.inHours == 1
                  ? '1 hour'
                  : '${d.inHours} hours',
            ),
          ),
      ],
    ),
  );
  if (length == null) return;
  final problem = await ref.read(liveShareProvider.notifier).start(conversationId, length, isE2e: isE2e);
  if (problem != null) messenger?.showSnackBar(SnackBar(content: Text(problem)));
}

/// Above the composer while I'm sharing live in this chat: how long is
/// left, and Stop. (Android also shows a "Sharing live location"
/// notification the whole time.)
class LiveShareBanner extends ConsumerStatefulWidget {
  const LiveShareBanner({super.key, required this.conversationId});

  final int conversationId;

  @override
  ConsumerState<LiveShareBanner> createState() => _LiveShareBannerState();
}

class _LiveShareBannerState extends ConsumerState<LiveShareBanner> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final share = ref.watch(liveShareProvider.select((s) => s[widget.conversationId]));
    if (share == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Container(
      color: colors.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.share_location, color: colors.onPrimaryContainer),
          const SizedBox(width: 8),
          Expanded(child: Text('You\'re sharing live location · ${timeLeft(share.until.difference(DateTime.now()))}')),
          TextButton(
            onPressed: () => ref.read(liveShareProvider.notifier).stop(widget.conversationId),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}
