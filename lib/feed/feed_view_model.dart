import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../data/services/api_service.dart';
import '../data/services/app_socket.dart';
import '../data/services/cursor_codec.dart';
import '../data/services/service_providers.dart';
import '../data/services/socket_provider.dart';
import '../models/models.dart';
import '../session/user_session.dart';

/// Mirrors news-feed-android's FeedViewModel.kt: ChangeNotifier is Flutter's
/// closest equivalent to Kotlin's StateFlow-backed ViewModel.
///
/// Feed state only, for one logged-in user. Login/logout and the socket moved
/// out (currentUserProvider, socketProvider), so this is created after login
/// with the user and socket already known, and thrown away on logout.
class FeedViewModel extends ChangeNotifier {
  final ApiService _api;
  final CurrentUser _user;
  late final StreamSubscription<Map<String, dynamic>> _socketSub;
  bool _disposed = false;

  FeedViewModel(this._api, this._user, AppSocket socket) {
    _socketSub = socket.events.listen((event) {
      if (event['type'] == 'feed_updated') _checkForNewPosts();
    });
    refresh();
  }

  String get currentUsername => _user.username;
  int get followerCount => _user.followerCount;
  bool isLoading = false;
  bool isPosting = false;
  List<Post> posts = [];
  String? nextCursor;
  String? error;
  /// The whole point of this app: shown right after a successful post.
  String? fanoutMessage;
  /// Set when the realtime socket signals a change and a check against
  /// GET /feed/{userId}/new confirms something's actually new.
  bool hasNewPosts = false;

  /// The socket only ever says "something changed" — it never carries the
  /// post itself. This turns that bare signal into an actual answer via the
  /// same GET /feed/{userId}/new endpoint a manual poll would use; the
  /// socket just decides *when* to ask.
  Future<void> _checkForNewPosts() async {
    if (posts.isEmpty) return;
    final top = posts.first;
    final since = CursorCodec.encode(top.createdAt, top.id);
    try {
      final page = await _api.getNewerFeed(_user.id, since: since, limit: 1);
      if (page.posts.isNotEmpty) {
        hasNewPosts = true;
        notifyListeners();
      }
    } catch (_) {
      // Best-effort — a failed "anything new?" check just means no banner.
    }
  }

  // This view model now dies on logout, possibly while a request is still in
  // flight; its late notifyListeners() must be a no-op, not a
  // "used after being disposed" error.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _socketSub.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final page = await _api.getFeed(_user.id, limit: _pageSize);
      posts = page.posts;
      nextCursor = page.nextCursor;
      hasNewPosts = false;
      isLoading = false;
      notifyListeners();
    } catch (e) {
      isLoading = false;
      error = 'Couldn\'t load feed: $e';
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (nextCursor == null) return;
    isLoading = true;
    notifyListeners();
    try {
      final page = await _api.getFeed(_user.id, limit: _pageSize, cursor: nextCursor);
      posts = [...posts, ...page.posts];
      nextCursor = page.nextCursor;
      isLoading = false;
      notifyListeners();
    } catch (e) {
      isLoading = false;
      error = 'Couldn\'t load more: $e';
      notifyListeners();
    }
  }

  Future<void> publishPost(String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    isPosting = true;
    error = null;
    notifyListeners();
    try {
      final response = await _api.createPost(authorId: _user.id, body: trimmed);
      isPosting = false;
      fanoutMessage = 'Fanned out to $followerCount followers in ${response.fanoutMs} ms';
      notifyListeners();
      await refresh();
    } catch (e) {
      isPosting = false;
      error = 'Couldn\'t post: $e';
      notifyListeners();
    }
  }

  void dismissFanoutMessage() {
    fanoutMessage = null;
    notifyListeners();
  }

  static const _pageSize = 20;
}

/// One FeedViewModel per logged-in user. A bridge until step 5 replaces it
/// with a Riverpod Notifier: Riverpod's legacy ChangeNotifierProvider rebuilds
/// widgets on notifyListeners() and calls dispose() for us. autoDispose: it
/// goes away with FeedScreen on logout.
final feedViewModelProvider = ChangeNotifierProvider.autoDispose.family<FeedViewModel, CurrentUser>(
  (ref, user) => FeedViewModel(
    ref.watch(apiServiceProvider),
    user,
    ref.watch(socketProvider(user.id)),
  ),
);
