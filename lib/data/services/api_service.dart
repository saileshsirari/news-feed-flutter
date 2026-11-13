import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../config/app_config.dart';
import '../../models/models.dart';

/// Service for the REST API: one method per endpoint, no state, no business
/// rules. The Dart equivalent of ApiClient.kt + NewsFeedApi.kt combined (no
/// Retrofit-style interface, since http + dart:convert needs no generated
/// client for a handful of routes).
///
/// The server address comes from [AppConfig], and the [http.Client] can be
/// swapped for a fake in tests.
class ApiService {
  ApiService(this._config, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final AppConfig _config;
  final http.Client _http;

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final filtered = query?.map((k, v) => MapEntry(k, v.toString()));
    return Uri.parse('${_config.apiBaseUrl}$path').replace(queryParameters: filtered);
  }

  Map<String, dynamic> _decodeObject(http.Response res) {
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, res.body);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  List<dynamic> _decodeList(http.Response res) {
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, res.body);
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  /// Who the access token belongs to (created on first sign-in).
  Future<User> getMe() async => User.fromJson(_decodeObject(await _http.get(_uri('/me'))));

  /// Someone's profile, with their counts.
  Future<User> getUser(int userId) async => User.fromJson(_decodeObject(await _http.get(_uri('/users/$userId'))));

  /// Someone's posts, newest first; pass the returned cursor for the next page.
  Future<FeedPage> getUserPosts(int authorId, {required int viewerId, String? cursor}) async {
    final res = await _http.get(_uri('/users/$authorId/posts', {'userId': viewerId, 'cursor': ?cursor}));
    return FeedPage.fromJson(_decodeObject(res));
  }

  /// Changes your own profile; only what's given changes. A blank
  /// [displayName] or [bio] clears it. [photoMediaId]: an uploaded image to
  /// use, or with [removePhoto], none.
  Future<User> updateProfile({
    required int userId,
    String? displayName,
    String? bio,
    int? photoMediaId,
    bool removePhoto = false,
  }) async {
    final request = http.Request('PATCH', _uri('/me/profile'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'userId': userId,
        'displayName': ?displayName,
        'bio': ?bio,
        if (removePhoto) 'avatarMediaId': null else 'avatarMediaId': ?photoMediaId,
      });
    return User.fromJson(_decodeObject(await http.Response.fromStream(await _http.send(request))));
  }

  /// Likes (or with [liked] false, unlikes) a post; returns the new count.
  Future<int> likePost(int postId, {required int userId, required bool liked}) async {
    final request = http.Request(liked ? 'PUT' : 'DELETE', _uri('/posts/$postId/like', {'userId': userId}))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'userId': userId});
    final res = await http.Response.fromStream(await _http.send(request));
    return _decodeObject(res)['likeCount'] as int;
  }

  /// Oldest first; pass the returned cursor for the next page.
  /// A page of a post's comments in reading order, three levels deep; with
  /// [under], that comment's own thread ("Continue this thread").
  Future<({List<PostComment> comments, String? nextCursor})> getComments(
    int postId,
    int userId, {
    String? cursor,
    int? under,
  }) async {
    final res = await _http.get(
      _uri('/posts/$postId/comments', {'userId': userId, 'cursor': ?cursor, 'under': ?under}),
    );
    final json = _decodeObject(res);
    return (
      comments: [for (final c in json['comments'] as List) PostComment.fromJson(c as Map<String, dynamic>)],
      nextCursor: json['nextCursor'] as String?,
    );
  }

  /// A comment on the post, or with [parentId], a reply.
  Future<PostComment> addComment(int postId, {required int userId, required String body, int? parentId}) async {
    final res = await _http.post(
      _uri('/posts/$postId/comments'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'body': body, 'parentId': ?parentId}),
    );
    return PostComment.fromJson(_decodeObject(res));
  }

  Future<void> deleteComment(int postId, int commentId, {required int userId}) async {
    final res = await _http.delete(_uri('/posts/$postId/comments/$commentId', {'userId': userId}));
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
  }

  /// Sets your reaction on a chat message, or removes it ([emoji] null).
  Future<void> react(int conversationId, int messageId, {required int userId, required String? emoji}) async {
    final request = http.Request(
      emoji == null ? 'DELETE' : 'PUT',
      _uri('/conversations/$conversationId/messages/$messageId/reaction', {'userId': userId}),
    )
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'userId': userId, 'emoji': ?emoji});
    final res = await http.Response.fromStream(await _http.send(request));
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
  }

  /// Uploads this device's public MLS key packages; [replace] drops its older
  /// ones first (a fresh identity). Returns how many it now has.
  Future<int> uploadKeyPackages(int deviceId, List<Uint8List> keyPackages, {bool replace = false}) async {
    final res = await _http.post(
      _uri('/e2e/key-packages'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'deviceId': deviceId,
        'keyPackages': [for (final p in keyPackages) base64Encode(p)],
        if (replace) 'replace': true,
      }),
    );
    return _decodeObject(res)['count'] as int;
  }

  /// How many key packages this device still has on the server.
  Future<int> keyPackageCount(int deviceId) async =>
      _decodeObject(await _http.get(_uri('/e2e/key-packages/count', {'deviceId': deviceId})))['count'] as int;

  /// One key package for each device of each of [userIds] (each handed out once).
  Future<({List<({int userId, int deviceId, Uint8List keyPackage})> keyPackages, List<({int userId, int deviceId})> missing})>
      claimKeyPackages(List<int> userIds) async {
    final res = await _http.post(
      _uri('/e2e/key-packages/claim'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userIds': userIds}),
    );
    final json = _decodeObject(res);
    return (
      keyPackages: [
        for (final p in json['keyPackages'] as List)
          (
            userId: (p as Map)['userId'] as int,
            deviceId: p['deviceId'] as int,
            keyPackage: base64Decode(p['keyPackage'] as String),
          ),
      ],
      missing: [
        for (final m in json['missing'] as List) (userId: (m as Map)['userId'] as int, deviceId: m['deviceId'] as int),
      ],
    );
  }

  /// Turns the chat end-to-end encrypted; returns the seq of its notice
  /// (this device reads the chat from there). 409 if it already was.
  Future<int> turnOnE2e(
    int conversationId, {
    required int deviceId,
    required String groupId,
    required int epoch,
    required Uint8List welcome,
    required List<({int userId, int deviceId})> recipients,
  }) async {
    final res = await _http.post(
      _uri('/conversations/$conversationId/e2e'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'deviceId': deviceId,
        'groupId': groupId,
        'epoch': epoch,
        'welcome': base64Encode(welcome),
        'recipients': [for (final r in recipients) {'userId': r.userId, 'deviceId': r.deviceId}],
      }),
    );
    return _decodeObject(res)['seq'] as int;
  }

  /// Encrypted chats this device was added to, waiting to be joined.
  Future<List<({int id, int conversationId, Uint8List welcome, int afterSeq, String groupId})>> e2eWelcomes(
    int deviceId,
  ) async {
    final res = await _http.get(_uri('/e2e/welcomes', {'deviceId': deviceId}));
    return [
      for (final w in _decodeList(res))
        (
          id: (w as Map)['id'] as int,
          conversationId: w['conversation_id'] as int,
          welcome: base64Decode(w['welcome'] as String),
          afterSeq: w['after_seq'] as int,
          groupId: w['mls_group_id'] as String,
        ),
    ];
  }

  Future<void> doneWithWelcome(int deviceId, int welcomeId) async {
    final res = await _http.delete(_uri('/e2e/welcomes/$welcomeId', {'deviceId': deviceId}));
    if (res.statusCode >= 400 && res.statusCode != 404) throw ApiException(res.statusCode, res.body);
  }

  /// An encrypted message (or group change) from this device; returns the
  /// server's message (its id and seq). 409 with currentEpoch if the group
  /// moved on.
  Future<Map<String, dynamic>> sendEncrypted(
    int conversationId, {
    required int deviceId,
    required Uint8List ciphertext,
    required int epoch,
    bool changesGroup = false,
    String? clientMessageId,
    List<int> mediaIds = const [],
  }) async {
    final res = await _http.post(
      _uri('/conversations/$conversationId/messages/encrypted'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'deviceId': deviceId,
        'ciphertext': base64Encode(ciphertext),
        'epoch': epoch,
        if (changesGroup) 'changesGroup': true,
        'clientMessageId': ?clientMessageId,
        if (mediaIds.isNotEmpty) 'mediaIds': mediaIds,
      }),
    );
    return _decodeObject(res);
  }

  /// Registers this install (or refreshes it) for the signed-in user;
  /// returns its id on the server (push addresses are stored against it).
  Future<int> registerDevice(String installId, {required String name, required String platform}) async {
    final res = await _http.put(
      _uri('/devices/$installId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'platform': platform}),
    );
    return _decodeObject(res)['id'] as int;
  }

  /// The server's public key for Web Push; null if it has none set up.
  Future<String?> getWebPushKey() async {
    final res = await _http.get(_uri('/push/web-key'));
    if (res.statusCode == 503) return null;
    return _decodeObject(res)['publicKey'] as String;
  }

  /// Where this device is reached for push: {kind: "webpush", subscription}
  /// or {kind: "fcm", token}.
  Future<void> registerPushEndpoint(int deviceId, Map<String, dynamic> address) async {
    final res = await _http.put(
      _uri('/push/endpoints/$deviceId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(address),
    );
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
  }

  Future<void> deletePushEndpoint(int deviceId) async {
    final res = await _http.delete(_uri('/push/endpoints/$deviceId'));
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
  }

  Future<User> getUserByUsername(String username) async {
    final res = await _http.get(_uri('/users', {'username': username}));
    return User.fromJson(_decodeObject(res));
  }

  Future<List<User>> listUsers({int limit = 50}) async {
    final res = await _http.get(_uri('/users', {'limit': limit}));
    return _decodeList(res).map((u) => User.fromJson(u as Map<String, dynamic>)).toList();
  }

  /// Ids of the users [userId] follows.
  Future<Set<int>> getFollowing(int userId) async {
    final res = await _http.get(_uri('/users/$userId/following'));
    return _decodeList(res).cast<int>().toSet();
  }

  Future<void> follow({required int followerId, required int followeeId}) =>
      _sendFollow('POST', followerId, followeeId);

  Future<void> unfollow({required int followerId, required int followeeId}) =>
      _sendFollow('DELETE', followerId, followeeId);

  Future<void> _sendFollow(String method, int followerId, int followeeId) async {
    final request = http.Request(method, _uri('/follows'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'followerId': followerId, 'followeeId': followeeId});
    final res = await http.Response.fromStream(await _http.send(request));
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
  }

  /// [mediaIds] come from a ready MediaDraftState, in display order.
  Future<CreatePostResponse> createPost({
    required int authorId,
    required String body,
    List<int> mediaIds = const [],
  }) async {
    final res = await _http.post(
      _uri('/posts'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'authorId': authorId, 'body': body, if (mediaIds.isNotEmpty) 'mediaIds': mediaIds}),
    );
    return CreatePostResponse.fromJson(_decodeObject(res));
  }

  Future<FeedPage> getFeed(int userId, {int limit = 20, String? cursor}) async {
    final res = await _http.get(_uri('/feed/$userId', {'limit': limit, if (cursor != null) 'cursor': cursor}));
    return FeedPage.fromJson(_decodeObject(res));
  }

  Future<NewerFeedPage> getNewerFeed(int userId, {required String since, int limit = 1}) async {
    final res = await _http.get(_uri('/feed/$userId/new', {'since': since, 'limit': limit}));
    return NewerFeedPage.fromJson(_decodeObject(res));
  }

  Future<Conversation> createConversation({
    required List<int> participantIds,
    required bool isGroup,
    String? name,
  }) async {
    final res = await _http.post(
      _uri('/conversations'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'participantIds': participantIds,
        'isGroup': isGroup,
        if (name != null) 'name': name,
      }),
    );
    return Conversation.fromJson(_decodeObject(res));
  }

  Future<List<ConversationSummary>> listConversations(int userId) async {
    final res = await _http.get(_uri('/conversations', {'userId': userId}));
    return _decodeList(res).map((c) => ConversationSummary.fromJson(c as Map<String, dynamic>)).toList();
  }

  Future<MessagePage> getMessages(int conversationId, int userId, {int limit = 30, String? cursor}) async {
    final res = await _http.get(
      _uri('/conversations/$conversationId/messages', {
        'userId': userId,
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
      }),
    );
    return MessagePage.fromJson(_decodeObject(res));
  }

  /// Sync: the messages after [afterSeq] (oldest first), or before
  /// [beforeSeq] (newest first), as the server sent them.
  /// [userId] can be null with a signed-in token (the server knows who it
  /// is), as in a push notification's background handler.
  Future<({List<Map<String, dynamic>> messages, bool hasMore})> getMessagesBySeq(
    int conversationId,
    int? userId, {
    int? afterSeq,
    int? beforeSeq,
    required int limit,
  }) async {
    final res = await _http.get(
      _uri('/conversations/$conversationId/messages', {
        'userId': ?userId,
        'limit': limit,
        'afterSeq': ?afterSeq,
        'beforeSeq': ?beforeSeq,
      }),
    );
    final json = _decodeObject(res);
    return (
      messages: (json['messages'] as List).cast<Map<String, dynamic>>(),
      hasMore: json['hasMore'] as bool? ?? false,
    );
  }

  /// [clientMessageId] identifies this send: sending again with the same
  /// one returns the first message instead of posting it twice.
  Future<ChatMessage> sendMessage(
    int conversationId, {
    required int senderId,
    required String body,
    String? clientMessageId,
    List<int> mediaIds = const [],
  }) async {
    final res = await _http.post(
      _uri('/conversations/$conversationId/messages'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'senderId': senderId,
        'body': body,
        'clientMessageId': ?clientMessageId,
        if (mediaIds.isNotEmpty) 'mediaIds': mediaIds,
      }),
    );
    return ChatMessage.fromJson(_decodeObject(res));
  }

  Future<List<Presence>> getPresence(Iterable<int> userIds) async {
    final res = await _http.get(_uri('/presence', {'userIds': userIds.join(',')}));
    return _decodeList(res).map((p) => Presence.fromJson(p as Map<String, dynamic>)).toList();
  }

  Future<List<ReadState>> getReadStates(int conversationId, int userId) async {
    final res = await _http.get(_uri('/conversations/$conversationId/reads', {'userId': userId}));
    return _decodeList(res).map((r) => ReadState.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<void> markRead(int conversationId, {required int userId, required int lastReadMessageId}) async {
    final res = await _http.put(
      _uri('/conversations/$conversationId/read'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'lastReadMessageId': lastReadMessageId}),
    );
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
  }

  /// One of this user's devices now has the conversation up to
  /// [lastDeliveredMessageId] (the sender's ✓✓).
  Future<void> markDelivered(int conversationId, {required int userId, required int lastDeliveredMessageId}) async {
    final res = await _http.put(
      _uri('/conversations/$conversationId/delivered'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'lastDeliveredMessageId': lastDeliveredMessageId}),
    );
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
  }

  Future<CallToken> getCallToken(int conversationId, int userId) async {
    final res = await _http.get(_uri('/conversations/$conversationId/call-token', {'userId': userId}));
    return CallToken.fromJson(_decodeObject(res));
  }

  Future<void> startRecording(int conversationId, int userId) async {
    final res = await _http.post(
      _uri('/conversations/$conversationId/recording/start'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId}),
    );
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
  }

  Future<void> stopRecording(int conversationId, int userId) async {
    final res = await _http.post(
      _uri('/conversations/$conversationId/recording/stop'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId}),
    );
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String body;
  ApiException(this.statusCode, this.body);

  /// The server's rate limit said "slow down" (HTTP 429).
  bool get isRateLimited => statusCode == 429;

  /// From a 429: how long until the server takes this again.
  Duration? get retryAfter {
    if (!isRateLimited) return null;
    try {
      final seconds = (jsonDecode(body) as Map<String, dynamic>)['retryAfterSeconds'] as int?;
      return seconds == null ? null : Duration(seconds: seconds);
    } on Object {
      return null;
    }
  }

  @override
  String toString() {
    if (isRateLimited) return tooFastMessage(retryAfter);
    return 'ApiException($statusCode): $body';
  }
}

/// What to tell someone who hit a rate limit.
String tooFastMessage(Duration? retryAfter) => retryAfter == null
    ? 'You\'re doing that too fast. Try again in a moment.'
    : 'You\'re doing that too fast. Try again in ${retryAfter.inSeconds} s.';
