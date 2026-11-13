import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/service_providers.dart';
import '../models/models.dart';
import '../session/current_user_provider.dart';

/// One profile page: the person, and their posts so far.
class ProfileState {
  const ProfileState({
    required this.user,
    this.posts = const [],
    this.nextCursor,
    this.isLoadingMore = false,
    this.error,
  });

  final User user;
  final List<Post> posts;

  /// Where the next page of posts starts; null once they've all loaded.
  final String? nextCursor;
  final bool isLoadingMore;

  /// A like or a page that failed, to show briefly.
  final String? error;

  ProfileState copyWith({
    User? user,
    List<Post>? posts,
    String? Function()? nextCursor,
    bool? isLoadingMore,
    String? Function()? error,
  }) => ProfileState(
    user: user ?? this.user,
    posts: posts ?? this.posts,
    nextCursor: nextCursor != null ? nextCursor() : this.nextCursor,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    error: error != null ? error() : this.error,
  );
}

/// Someone's profile, keyed by their id: loads them and their first page
/// of posts together, then more posts on demand. Likes and comment counts
/// change here the same way they do in the feed.
class ProfileNotifier extends AsyncNotifier<ProfileState> {
  ProfileNotifier(this.userId);

  final int userId;

  int get _viewerId => ref.read(currentUserProvider).requireValue!.id;

  @override
  Future<ProfileState> build() async {
    final api = ref.watch(apiServiceProvider);
    final viewerId = ref.watch(currentUserProvider).requireValue!.id;
    final (user, page) = await (api.getUser(userId), api.getUserPosts(userId, viewerId: viewerId)).wait;
    return ProfileState(user: user, posts: page.posts, nextCursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.nextCursor == null || current.isLoadingMore) return;
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final page = await ref
          .read(apiServiceProvider)
          .getUserPosts(userId, viewerId: _viewerId, cursor: current.nextCursor);
      if (!ref.mounted) return;
      final now = state.requireValue;
      state = AsyncData(
        now.copyWith(posts: [...now.posts, ...page.posts], nextCursor: () => page.nextCursor, isLoadingMore: false),
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = AsyncData(state.requireValue.copyWith(isLoadingMore: false, error: () => 'Couldn\'t load more posts'));
    }
  }

  /// After you saved your own profile: show what the server now has.
  void showEdited(User user) {
    final current = state.value;
    if (current != null) state = AsyncData(current.copyWith(user: user));
  }

  Future<void> toggleLike(int postId) async {
    final before = _post(postId);
    if (before == null) return;
    final liked = !before.likedByMe;
    _replace(before.copyWith(likedByMe: liked, likeCount: (before.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 30)));
    try {
      final count = await ref.read(apiServiceProvider).likePost(postId, userId: _viewerId, liked: liked);
      if (!ref.mounted) return;
      final now = _post(postId);
      if (now != null) _replace(now.copyWith(likeCount: count));
    } catch (_) {
      if (!ref.mounted) return;
      _replace(before);
      state = AsyncData(state.requireValue.copyWith(error: () => 'Couldn\'t ${liked ? 'like' : 'unlike'} that post'));
    }
  }

  void setCommentCount(int postId, int count) {
    final post = _post(postId);
    if (post != null) _replace(post.copyWith(commentCount: count));
  }

  void dismissError() {
    final current = state.value;
    if (current?.error != null) state = AsyncData(current!.copyWith(error: () => null));
  }

  Post? _post(int postId) {
    for (final p in state.value?.posts ?? const <Post>[]) {
      if (p.id == postId) return p;
    }
    return null;
  }

  void _replace(Post post) {
    final current = state.requireValue;
    state = AsyncData(current.copyWith(posts: [for (final p in current.posts) p.id == post.id ? post : p]));
  }
}

/// autoDispose: a profile is fetched fresh each time it's opened.
final profileProvider = AsyncNotifierProvider.autoDispose.family<ProfileNotifier, ProfileState, int>(
  ProfileNotifier.new,
);
