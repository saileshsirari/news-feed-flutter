import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import 'presence_notifier.dart';

/// "online", "last seen 5 min ago", or null if never seen.
String? describePresence(Presence? presence, {DateTime? now}) {
  if (presence == null) return null;
  if (presence.online) return 'online';
  final lastSeenAt = presence.lastSeenAt;
  if (lastSeenAt == null) return null;
  final ago = (now ?? DateTime.now()).difference(DateTime.fromMillisecondsSinceEpoch(lastSeenAt));
  return switch (ago) {
    _ when ago.inMinutes < 1 => 'last seen just now',
    _ when ago.inHours < 1 => 'last seen ${ago.inMinutes} min ago',
    _ when ago.inDays < 1 => 'last seen ${ago.inHours} h ago',
    _ when ago.inDays == 1 => 'last seen yesterday',
    _ => 'last seen ${ago.inDays} days ago',
  };
}

/// Starts tracking [userId] when first built; the rest of the screen just
/// watches. A State, so tracking happens once, not on every rebuild.
abstract class _PresenceWidget extends ConsumerStatefulWidget {
  const _PresenceWidget({super.key, required this.userId});

  final int userId;
}

abstract class _PresenceWidgetState<T extends _PresenceWidget> extends ConsumerState<T> {
  @override
  void initState() {
    super.initState();
    ref.read(presenceProvider.notifier).track([widget.userId]);
  }

  Presence? get presence => ref.watch(presenceProvider.select((all) => all[widget.userId]));
}

/// [child] (an avatar) with a green dot in the corner while [userId] is online.
class OnlineDot extends _PresenceWidget {
  const OnlineDot({super.key, required super.userId, required this.child});

  final Widget child;

  /// The dot itself, for tests.
  static const dotKey = ValueKey('online-dot');

  @override
  ConsumerState<OnlineDot> createState() => _OnlineDotState();
}

class _OnlineDotState extends _PresenceWidgetState<OnlineDot> {
  @override
  Widget build(BuildContext context) {
    final online = presence?.online ?? false;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (online)
          Positioned(
            right: -1,
            bottom: -1,
            child: Semantics(
              label: 'online',
              child: Container(
                key: OnlineDot.dotKey,
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// "online" / "last seen …" under a 1:1 chat's title; nothing if unknown.
class PresenceSubtitle extends _PresenceWidget {
  const PresenceSubtitle({super.key, required super.userId});

  @override
  ConsumerState<PresenceSubtitle> createState() => _PresenceSubtitleState();
}

class _PresenceSubtitleState extends _PresenceWidgetState<PresenceSubtitle> {
  @override
  Widget build(BuildContext context) {
    final text = describePresence(presence);
    if (text == null) return const SizedBox.shrink();
    return Text(text, style: Theme.of(context).textTheme.bodySmall);
  }
}
