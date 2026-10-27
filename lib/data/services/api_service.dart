import 'dart:convert';
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

  Future<User> getUserByUsername(String username) async {
    final res = await _http.get(_uri('/users', {'username': username}));
    return User.fromJson(_decodeObject(res));
  }

  Future<List<User>> listUsers({int limit = 50}) async {
    final res = await _http.get(_uri('/users', {'limit': limit}));
    return _decodeList(res).map((u) => User.fromJson(u as Map<String, dynamic>)).toList();
  }

  Future<CreatePostResponse> createPost({required int authorId, required String body}) async {
    final res = await _http.post(
      _uri('/posts'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'authorId': authorId, 'body': body}),
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

  Future<ChatMessage> sendMessage(int conversationId, {required int senderId, required String body}) async {
    final res = await _http.post(
      _uri('/conversations/$conversationId/messages'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'senderId': senderId, 'body': body}),
    );
    return ChatMessage.fromJson(_decodeObject(res));
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

  @override
  String toString() => 'ApiException($statusCode): $body';
}
