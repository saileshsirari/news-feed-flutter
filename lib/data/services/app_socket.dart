import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../config/app_config.dart';

/// One persistent connection carrying every realtime event this app cares
/// about — feed_updated (from FeedSocket.kt's original job), plus
/// message_created and read_receipt_updated (chat's live nudges, see
/// chatConsumer.ts). It's one server-side WebSocket per user regardless of
/// how many kinds of events flow over it, so this is one client-side
/// connection too, not a separate socket per feature the way a first pass
/// might tempt you to build. Exposes decoded JSON events as a broadcast
/// stream; each screen's view model filters for the "type" it cares about.
///
/// Reconnects by itself. Before, a dropped connection (server restart,
/// phone switching networks, a long time in the background) silently ended
/// all live updates until the app was restarted. Now it retries with
/// backoff, and after each successful reconnect emits a synthetic
/// `{"type": "reconnected"}` event: anything sent while it was down is lost
/// (the server doesn't replay), so listeners reload on that event to catch
/// up. [events] is the same stream across reconnects, so listeners never
/// need to resubscribe.
///
/// Compose/Android: ≈ an OkHttp WebSocket wrapper that reconnects in
/// `onFailure`/`onClosed` and exposes a long-lived `SharedFlow` of events.
class AppSocket {
  final int userId;
  final AppConfig _config;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  /// True after [disconnect]: stop reconnecting for good.
  bool _closed = false;
  bool _hasConnectedBefore = false;
  int _attempt = 0;
  Timer? _retryTimer;

  /// [accessToken] gives the signed-in user's token (asked again on every
  /// reconnect, so it's always a fresh one); without it, or when it gives
  /// null, the socket connects as a test account, by user id only.
  AppSocket(this.userId, this._config, {this.accessToken});

  final Future<String?> Function()? accessToken;

  /// What the server answers to; [tokenProtocolPrefix] carries the token.
  static const protocol = 'newsfeed';
  static const tokenProtocolPrefix = 'bearer.';

  Stream<Map<String, dynamic>> get events => _controller.stream;

  /// Posts whose comments are open here, and how many sheets show each
  /// (a thread opened from another sheet of the same post counts twice).
  /// They get live changes ("post_comments" events), and are asked for
  /// again after a reconnect.
  final _watchedPosts = <int, int>{};
  Set<int> get watchedPosts => Set.unmodifiable(_watchedPosts.keys);

  /// A comments sheet for [postId] opened: send its changes here.
  void watchPost(int postId) {
    final count = _watchedPosts[postId] ?? 0;
    _watchedPosts[postId] = count + 1;
    if (count == 0) _send({'type': 'watch_post', 'postId': postId});
  }

  /// It closed; the last one to close stops the changes.
  void unwatchPost(int postId) {
    final count = _watchedPosts[postId];
    if (count == null) return;
    if (count > 1) {
      _watchedPosts[postId] = count - 1;
      return;
    }
    _watchedPosts.remove(postId);
    _send({'type': 'unwatch_post', 'postId': postId});
  }

  /// Best effort: if not connected now, the reconnect sends the watches anyway.
  void _send(Map<String, Object?> message) {
    try {
      _channel?.sink.add(jsonEncode(message));
    } catch (_) {}
  }

  /// Wait before retry number [attempt]: 1s, 2s, 4s, ... capped at 30s.
  static Duration retryDelay(int attempt) {
    final seconds = 1 << attempt.clamp(0, 5);
    return Duration(seconds: seconds > 30 ? 30 : seconds);
  }

  void connect() {
    if (_closed) return;
    _connectWithToken().catchError((Object _) => _scheduleReconnect());
  }

  Future<void> _connectWithToken() async {
    final token = await accessToken?.call();
    if (_closed) return;
    // A browser's WebSocket can't set an Authorization header, so the token
    // rides in the subprotocol list instead (the server picks "newsfeed"
    // and never echoes the token back). Same on every platform, for one
    // code path.
    final protocols = token == null ? null : [protocol, '$tokenProtocolPrefix$token'];
    // Same host as the REST API, from the one AppConfig — the whole reason
    // "can't log in on a real phone" happened was the address living in two
    // places and only one getting updated.
    final channel = WebSocketChannel.connect(_config.webSocketUri(userId: userId), protocols: protocols);
    _channel = channel;
    channel.ready.then(
      (_) {
        if (_closed || _channel != channel) return;
        _attempt = 0;
        // A new connection starts with no watches on the server: ask again.
        for (final postId in _watchedPosts.keys) {
          _send({'type': 'watch_post', 'postId': postId});
        }
        if (_hasConnectedBefore) _controller.add(const {'type': 'reconnected'});
        _hasConnectedBefore = true;
      },
      // A failed connect also ends the stream below, which schedules the
      // retry; this handler only keeps the error from going unhandled.
      onError: (_) {},
    );
    _channelSub = channel.stream.listen(
      (raw) {
        try {
          _controller.add(jsonDecode(raw as String) as Map<String, dynamic>);
        } catch (_) {
          // Not JSON — ignore rather than crash the whole connection.
        }
      },
      onError: (_) {},
      onDone: () {
        if (_channel == channel) _scheduleReconnect();
      },
    );
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _channelSub?.cancel();
    _channel = null;
    _retryTimer?.cancel();
    _retryTimer = Timer(retryDelay(_attempt++), connect);
  }

  void disconnect() {
    _closed = true;
    _retryTimer?.cancel();
    _channelSub?.cancel();
    _channel?.sink.close();
    _channel = null;
  }
}
