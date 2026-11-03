import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/service_providers.dart';
import '../session/current_user_provider.dart';

/// Who the logged-in user follows, and which follow/unfollow requests are
/// still on their way to the server.
class FollowingState {
  const FollowingState({this.isLoaded = false, this.followeeIds = const {}, this.pendingIds = const {}});

  /// False until the first load finishes; buttons stay disabled until then,
  /// so they never show "Follow" for someone you already follow.
  final bool isLoaded;
  final Set<int> followeeIds;
  final Set<int> pendingIds;

  bool follows(int userId) => followeeIds.contains(userId);
  bool isPending(int userId) => pendingIds.contains(userId);

  FollowingState copyWith({bool? isLoaded, Set<int>? followeeIds, Set<int>? pendingIds}) => FollowingState(
        isLoaded: isLoaded ?? this.isLoaded,
        followeeIds: followeeIds ?? this.followeeIds,
        pendingIds: pendingIds ?? this.pendingIds,
      );
}

/// Its own feature, not part of contacts: any screen that lists people can
/// show a FollowButton, and they all share this one state.
///
/// Compose/Android: ≈ a `@Singleton` FollowRepository exposing a
/// `StateFlow<Set<Int>>`, with optimistic updates.
class FollowingNotifier extends Notifier<FollowingState> {
  late int _currentUserId;

  @override
  FollowingState build() {
    // ref.read, not watch: see ConversationNotifier.build.
    _currentUserId = ref.read(currentUserProvider).requireValue!.id;
    _load();
    return const FollowingState();
  }

  Future<void> _load() async {
    try {
      final ids = await ref.read(apiServiceProvider).getFollowing(_currentUserId);
      if (!ref.mounted) return;
      state = state.copyWith(isLoaded: true, followeeIds: ids);
    } catch (_) {
      // Leave the buttons disabled; the next screen visit tries again.
    }
  }

  /// Flips following [userId], showing the result at once and undoing it if
  /// the server refuses. Returns whether it worked, so the caller can say so.
  Future<bool> toggle(int userId) async {
    if (!state.isLoaded || state.isPending(userId)) return false;
    final wasFollowing = state.follows(userId);
    state = state.copyWith(
      followeeIds: wasFollowing ? ({...state.followeeIds}..remove(userId)) : {...state.followeeIds, userId},
      pendingIds: {...state.pendingIds, userId},
    );
    final api = ref.read(apiServiceProvider);
    try {
      if (wasFollowing) {
        await api.unfollow(followerId: _currentUserId, followeeId: userId);
      } else {
        await api.follow(followerId: _currentUserId, followeeId: userId);
      }
      if (ref.mounted) state = state.copyWith(pendingIds: {...state.pendingIds}..remove(userId));
      return true;
    } catch (_) {
      if (!ref.mounted) return false;
      state = state.copyWith(
        followeeIds: wasFollowing ? {...state.followeeIds, userId} : ({...state.followeeIds}..remove(userId)),
        pendingIds: {...state.pendingIds}..remove(userId),
      );
      return false;
    }
  }
}

/// autoDispose: reloaded fresh each time a screen with follow buttons opens,
/// so it never shows stale follows from before a logout.
final followingProvider = NotifierProvider.autoDispose<FollowingNotifier, FollowingState>(FollowingNotifier.new);
