import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../network/api_client.dart';
import '../network/app_socket.dart';
import '../network/cursor_codec.dart';
import '../session/user_session.dart';

/// Mirrors news-feed-android's FeedViewModel.kt: ChangeNotifier is Flutter's
/// closest equivalent to Kotlin's StateFlow-backed ViewModel for something
/// this simple (see pubspec.yaml's note on Provider vs. Riverpod/Bloc).
class FeedViewModel extends ChangeNotifier {
  final ApiClient _api;
  final UserSession _session;
  AppSocket? _socket;

  FeedViewModel(this._api, this._session) {
    _init();
  }

  bool loggedIn = false;
  String currentUsername = '';
  int followerCount = 0;
  bool loggingIn = false;
  String? loginError;
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

  int? _currentUserId;
  int? get currentUserId => _currentUserId;

  /// Shared with the chat feature — one WebSocket per logged-in user carries
  /// both feed_updated and chat events (message_created,
  /// read_receipt_updated); see app_socket.dart's doc comment for why this
  /// isn't a second, separate connection.
  AppSocket? get socket => _socket;

  Future<void> _init() async {
    final user = await _session.current();
    if (user == null) return;
    _currentUserId = user.id;
    loggedIn = true;
    currentUsername = user.username;
    followerCount = user.followerCount;
    // Connect before notifying: HomeScreen watches currentUserId and, the
    // moment it's non-null, builds ConversationsListScreen with today's
    // `socket` value baked in at construction time (see its
    // ChangeNotifierProvider) — never re-read afterward. notifyListeners()
    // first, socket second used to leave that provider holding a permanent
    // null, silently killing every live chat/read-receipt push for the rest
    // of the session (REST calls still worked, so nothing looked broken
    // until you noticed live updates never arrived).
    _connectRealtime(user.id);
    notifyListeners();
    await refresh();
  }

  void _connectRealtime(int userId) {
    _socket?.disconnect();
    _socket = AppSocket(userId)..connect();
    _socket!.events.listen((event) {
      if (event['type'] == 'feed_updated') _checkForNewPosts();
    });
  }

  /// The socket only ever says "something changed" — it never carries the
  /// post itself. This turns that bare signal into an actual answer via the
  /// same GET /feed/{userId}/new endpoint a manual poll would use; the
  /// socket just decides *when* to ask.
  Future<void> _checkForNewPosts() async {
    if (_currentUserId == null || posts.isEmpty) return;
    final top = posts.first;
    final since = CursorCodec.encode(top.createdAt, top.id);
    try {
      final page = await _api.getNewerFeed(_currentUserId!, since: since, limit: 1);
      if (page.posts.isNotEmpty) {
        hasNewPosts = true;
        notifyListeners();
      }
    } catch (_) {
      // Best-effort — a failed "anything new?" check just means no banner.
    }
  }

  @override
  void dispose() {
    _socket?.disconnect();
    super.dispose();
  }

  Future<void> login(String username) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) return;
    loggingIn = true;
    loginError = null;
    notifyListeners();
    try {
      final user = await _api.getUserByUsername(trimmed);
      await _session.save(user);
      _currentUserId = user.id;
      loggedIn = true;
      currentUsername = user.username;
      followerCount = user.followerCount;
      loggingIn = false;
      posts = [];
      nextCursor = null;
      // Same ordering fix as _init() — see its comment.
      _connectRealtime(user.id);
      notifyListeners();
      await refresh();
    } catch (e) {
      loggingIn = false;
      loginError = 'Couldn\'t find "$trimmed": $e';
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _socket?.disconnect();
    _socket = null;
    await _session.clear();
    loggedIn = false;
    currentUsername = '';
    followerCount = 0;
    posts = [];
    nextCursor = null;
    _currentUserId = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_currentUserId == null) return;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final page = await _api.getFeed(_currentUserId!, limit: _pageSize);
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
    if (_currentUserId == null || nextCursor == null) return;
    isLoading = true;
    notifyListeners();
    try {
      final page = await _api.getFeed(_currentUserId!, limit: _pageSize, cursor: nextCursor);
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
    if (_currentUserId == null || trimmed.isEmpty) return;
    isPosting = true;
    error = null;
    notifyListeners();
    try {
      final response = await _api.createPost(authorId: _currentUserId!, body: trimmed);
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
