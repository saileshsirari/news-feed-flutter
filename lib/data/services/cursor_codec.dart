import 'dart:convert';

/// Mirrors news-feed-android's CursorCodec.kt exactly — same "createdAt:id"
/// payload, unpadded URL-safe base64. The server treats cursors as opaque,
/// but the client needs to *produce* one from the newest post it already has
/// to ask "is there anything newer than this?" (see FeedViewModel).
class CursorCodec {
  static String encode(int createdAt, int id) {
    final bytes = utf8.encode('$createdAt:$id');
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
