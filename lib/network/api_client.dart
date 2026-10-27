import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

/// Thin REST wrapper — the Dart equivalent of ApiClient.kt + NewsFeedApi.kt
/// combined (no Retrofit-style interface here, just plain methods, since
/// http+dart:convert doesn't need a generated client for a handful of routes).
class ApiClient {
  /// Points at the deployed VM — reachable from any network (WiFi or
  /// cellular), not just your LAN, since it's a real public host behind
  /// Caddy's TLS termination. Swap back to 'http://10.187.177.226:3000'
  /// (get the current LAN IP with `ipconfig getifaddr en0` if it's changed)
  /// to test against your Mac instead — 10.0.2.2 only exists inside the
  /// Android *emulator* as its alias for the host's localhost, and resolves
  /// to nothing on real hardware, which is why that address only ever worked
  /// there and not on a real phone.
  static const String baseUrl = 'https://150-230-234-113.sslip.io';

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final filtered = query?.map((k, v) => MapEntry(k, v.toString()));
    return Uri.parse('$baseUrl$path').replace(queryParameters: filtered);
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

  Future<User> getUserByUsername(String username) async {
    final res = await http.get(_uri('/users', {'username': username}));
    return User.fromJson(_decodeObject(res));
  }

  Future<List<User>> listUsers({int limit = 50}) async {
    final res = await http.get(_uri('/users', {'limit': limit}));
    return _decodeList(res).map((u) => User.fromJson(u as Map<String, dynamic>)).toList();
  }

  Future<CreatePostResponse> createPost({required int authorId, required String body}) async {
    final res = await http.post(
      _uri('/posts'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'authorId': authorId, 'body': body}),
    );
    return CreatePostResponse.fromJson(_decodeObject(res));
  }

  Future<FeedPage> getFeed(int userId, {int limit = 20, String? cursor}) async {
    final res = await http.get(_uri('/feed/$userId', {'limit': limit, if (cursor != null) 'cursor': cursor}));
    return FeedPage.fromJson(_decodeObject(res));
  }

  Future<NewerFeedPage> getNewerFeed(int userId, {required String since, int limit = 1}) async {
    final res = await http.get(_uri('/feed/$userId/new', {'since': since, 'limit': limit}));
    return NewerFeedPage.fromJson(_decodeObject(res));
  }

  Future<Conversation> createConversation({
    required List<int> participantIds,
    required bool isGroup,
    String? name,
  }) async {
    final res = await http.post(
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
    final res = await http.get(_uri('/conversations', {'userId': userId}));
    return _decodeList(res).map((c) => ConversationSummary.fromJson(c as Map<String, dynamic>)).toList();
  }

  Future<MessagePage> getMessages(int conversationId, int userId, {int limit = 30, String? cursor}) async {
    final res = await http.get(
      _uri('/conversations/$conversationId/messages', {
        'userId': userId,
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
      }),
    );
    return MessagePage.fromJson(_decodeObject(res));
  }

  Future<ChatMessage> sendMessage(int conversationId, {required int senderId, required String body}) async {
    final res = await http.post(
      _uri('/conversations/$conversationId/messages'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'senderId': senderId, 'body': body}),
    );
    return ChatMessage.fromJson(_decodeObject(res));
  }

  Future<List<ReadState>> getReadStates(int conversationId, int userId) async {
    final res = await http.get(_uri('/conversations/$conversationId/reads', {'userId': userId}));
    return _decodeList(res).map((r) => ReadState.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<void> markRead(int conversationId, {required int userId, required int lastReadMessageId}) async {
    final res = await http.put(
      _uri('/conversations/$conversationId/read'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'lastReadMessageId': lastReadMessageId}),
    );
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
  }

  Future<CallToken> getCallToken(int conversationId, int userId) async {
    final res = await http.get(_uri('/conversations/$conversationId/call-token', {'userId': userId}));
    return CallToken.fromJson(_decodeObject(res));
  }

  Future<void> startRecording(int conversationId, int userId) async {
    final res = await http.post(
      _uri('/conversations/$conversationId/recording/start'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId}),
    );
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
  }

  Future<void> stopRecording(int conversationId, int userId) async {
    final res = await http.post(
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

  @override
  String toString() => 'ApiException($statusCode): $body';
}
