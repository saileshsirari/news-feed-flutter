import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/cursor_codec.dart';
import '../data/services/service_providers.dart';
import '../data/services/socket_provider.dart';
import '../models/models.dart';
import '../session/current_user_provider.dart';
import '../session/user_session.dart';

/// Everything FeedScreen draws, as one immutable value (see
/// ConversationState for why: Riverpod only notices `state = newValue`).
///
/// Compose/Android: ≈ `data class FeedUiState(...)`.
class FeedState {
  const FeedState({
    required this.user,
    this.isLoading = true,
    this.isPosting = false,
    this.posts = const [],
    this.nextCursor,
    this.error,
    this.fanoutMessage,
    this.hasNewPosts = false,
  });

  /// Who's logged in, for the app bar and the fanout message.
  final CurrentUser user;
  final bool isLoading;
  final bool isPosting;
  final List<Post> posts;
  final String? nextCursor;
  final String? error;

  /// The whole point of this app: shown right after a successful post.
  final String? fanoutMessage;

  /// Set when the realtime socket signals a change and a check against
  /// GET /feed/{userId}/new confirms something's actually new.
  final bool hasNewPosts;

  /// The nullable fields use a sentinel so `copyWith(error: null)` etc. can
  /// clear them.
  FeedState copyWith({
    bool? isLoading,
    bool? isPosting,
    List<Post>? posts,
    Object? nextCursor = _keep,
    Object? error = _keep,
    Object? fanoutMessage = _keep,
    bool? hasNewPosts,
  }) {
    return FeedState(
      user: user,
      isLoading: isLoading ?? this.isLoading,
      isPosting: isPosting ?? this.isPosting,
      posts: posts ?? this.posts,
      nextCursor: identical(nextCursor, _keep) ? this.nextCursor : nextCursor as String?,
      error: identical(error, _keep) ? this.error : error as String?,
      fanoutMessage: identical(fanoutMessage, _keep) ? this.fanoutMessage : fanoutMessage as String?,
      hasNewPosts: hasNewPosts ?? this.hasNewPosts,
    );
  }

  static const _keep = Object();
}

/// Mirrors news-feed-android's FeedViewModel.kt. Feed state only, for the
/// logged-in user; login/logout and the socket live in currentUserProvider
/// and socketProvider.
///
/// Compose/Android: ≈ `@HiltViewModel class FeedViewModel` with a
/// `StateFlow<FeedUiState>`.
class FeedNotifier extends Notifier<FeedState> {
  // A field, not `state.user.id`: _fetchFirstPage() starts inside build(),
  // before `state` exists, and reading `state` there throws.
  late int _userId;

  /// Posts this user just published that the server's feed doesn't include
  /// yet. Fanout happens in the background a moment after POST /posts
  /// returns (and GET /feed may serve a cached page until then), so a
  /// refresh in that window would otherwise make your own new post vanish.
  final _unconfirmedOwnPosts = <Post>[];

  @override
  FeedState build() {
    // ref.read, not watch: the user can't change while FeedScreen exists
    // (see ConversationNotifier.build).
    final user = ref.read(currentUserProvider).requireValue!;
    _userId = user.id;
    final sub = ref.watch(socketProvider(user.id)).events.listen((event) {
      if (event['type'] == 'feed_updated') _checkForNewPostsWithRetry();
      // Missed any feed_updated while disconnected? Ask once.
      if (event['type'] == 'reconnected') _checkForNewPosts();
    });
    ref.onDispose(sub.cancel);

    // Async: only touches `state` after its first await (see
    // ConversationNotifier.build).
    _fetchFirstPage();
    return FeedState(user: user);
  }

  /// The server sends feed_updated when a post is *created*, before its
  /// background fanout has put it in anyone's feed (fanoutService.ts), so
  /// asking right away usually finds nothing. Ask again a little later
  /// instead of missing the post until the next manual refresh.
  Future<void> _checkForNewPostsWithRetry() async {
    for (final delay in const [Duration.zero, Duration(seconds: 2), Duration(seconds: 5)]) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (!ref.mounted || state.hasNewPosts) return;
      if (await _checkForNewPosts()) return;
    }
  }

  /// The socket only ever says "something changed" — it never carries the
  /// post itself. This turns that bare signal into an actual answer via the
  /// same GET /feed/{userId}/new endpoint a manual poll would use; the
  /// socket just decides *when* to ask. Returns whether anything was new.
  Future<bool> _checkForNewPosts() async {
    if (state.posts.isEmpty) return false;
    final top = state.posts.first;
    final since = CursorCodec.encode(top.createdAt, top.id);
    try {
      final page = await ref.read(apiServiceProvider).getNewerFeed(_userId, since: since, limit: 1);
      if (!ref.mounted || page.posts.isEmpty) return false;
      state = state.copyWith(hasNewPosts: true);
      return true;
    } catch (_) {
      // Best-effort — a failed "anything new?" check just means no banner.
      return false;
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    await _fetchFirstPage();
  }

  Future<void> _fetchFirstPage() async {
    try {
      final page = await ref.read(apiServiceProvider).getFeed(_userId, limit: _pageSize);
      if (!ref.mounted) return;
      // Once the server's page has an own post, it's confirmed; until then,
      // keep showing it on top.
      final serverIds = page.posts.map((p) => p.id).toSet();
      _unconfirmedOwnPosts.removeWhere((p) => serverIds.contains(p.id));
      final posts = [..._unconfirmedOwnPosts, ...page.posts];
      state = state.copyWith(posts: posts, nextCursor: page.nextCursor, hasNewPosts: false, isLoading: false);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isLoading: false, error: 'Couldn\'t load feed: $e');
    }
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (cursor == null) return;
    state = state.copyWith(isLoading: true);
    try {
      final page = await ref.read(apiServiceProvider).getFeed(_userId, limit: _pageSize, cursor: cursor);
      if (!ref.mounted) return;
      state = state.copyWith(posts: [...state.posts, ...page.posts], nextCursor: page.nextCursor, isLoading: false);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isLoading: false, error: 'Couldn\'t load more: $e');
    }
  }

  Future<void> publishPost(String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(isPosting: true, error: null);
    try {
      final response = await ref.read(apiServiceProvider).createPost(authorId: _userId, body: trimmed);
      if (!ref.mounted) return;
      // Show it right away from the POST response. The old code refreshed
      // here instead, which usually got a feed from before the fanout and
      // so didn't include the post you'd just written.
      _unconfirmedOwnPosts.insert(0, response.post);
      state = state.copyWith(
        isPosting: false,
        posts: [response.post, ...state.posts],
        fanoutMessage: 'Fanned out to ${state.user.followerCount} followers in ${response.fanoutMs} ms',
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isPosting: false, error: 'Couldn\'t post: $e');
    }
  }

  void dismissFanoutMessage() {
    state = state.copyWith(fanoutMessage: null);
  }

  static const _pageSize = 20;
}

/// autoDispose: goes away with FeedScreen on logout (≈ ViewModel cleared).
/// No family any more: like the chat notifiers, it reads the user itself.
final feedProvider = NotifierProvider.autoDispose<FeedNotifier, FeedState>(FeedNotifier.new);
