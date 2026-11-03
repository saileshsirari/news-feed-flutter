import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/service_providers.dart';
import '../data/services/socket_provider.dart';
import '../models/models.dart';
import '../session/current_user_provider.dart';

/// Who's online, for every user some screen is showing. Screens [track] the
/// users they show; their current state is fetched once, and after that
/// changes arrive as presence_changed socket events (the server sends them
/// for people you have a 1:1 chat with). After a reconnect everything
/// tracked is fetched again, since changes may have been missed.
///
/// Compose/Android: ≈ a repository exposing `StateFlow<Map<Int, Presence>>`,
/// fed by the socket and refreshed on reconnect.
class PresenceNotifier extends Notifier<Map<int, Presence>> {
  final _tracked = <int>{};
  final _toFetch = <int>{};
  bool _fetchScheduled = false;

  @override
  Map<int, Presence> build() {
    // ref.read, not watch: see ConversationNotifier.build.
    final userId = ref.read(currentUserProvider).requireValue!.id;
    final sub = ref.watch(socketProvider(userId)).events.listen((event) {
      switch (event['type']) {
        case 'presence_changed':
          final presence = Presence.fromJson(event);
          state = {...state, presence.userId: presence};
        case 'reconnected':
          _fetch(_tracked);
      }
    });
    ref.onDispose(sub.cancel);
    return const {};
  }

  /// Starts showing [userIds]' presence. Calls made while a screen builds
  /// (one per row) are gathered into a single request.
  void track(Iterable<int> userIds) {
    final fresh = userIds.where(_tracked.add).toList();
    if (fresh.isEmpty) return;
    _toFetch.addAll(fresh);
    if (_fetchScheduled) return;
    _fetchScheduled = true;
    scheduleMicrotask(() {
      _fetchScheduled = false;
      final batch = {..._toFetch};
      _toFetch.clear();
      _fetch(batch);
    });
  }

  Future<void> _fetch(Set<int> userIds) async {
    if (userIds.isEmpty) return;
    try {
      final found = await ref.read(apiServiceProvider).getPresence(userIds);
      if (!ref.mounted) return;
      state = {...state, for (final p in found) p.userId: p};
    } catch (_) {
      // Best-effort: no dot or "last seen" until the next reconnect.
    }
  }
}

/// autoDispose: gone with the chat screens (≈ ViewModel cleared).
final presenceProvider = NotifierProvider.autoDispose<PresenceNotifier, Map<int, Presence>>(PresenceNotifier.new);
