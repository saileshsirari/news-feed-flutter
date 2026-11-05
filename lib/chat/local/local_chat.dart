import 'dart:convert';

import 'package:chat_store/chat_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/api_service.dart';
import '../../data/services/service_providers.dart';
import '../../models/models.dart';
import '../../session/current_user_provider.dart';

/// Plugs the app into chat_store: how to reach the server (this API), and
/// how a stored message becomes a ChatMessage again (its JSON).

/// The server's message JSON as chat_store keeps it.
RemoteMessage remoteMessageFrom(Map<String, dynamic> json) => RemoteMessage(
  conversationId: json['conversation_id'] as int,
  seq: json['seq'] as int,
  messageId: json['id'] as int,
  body: json['body'] as String,
  createdAt: json['created_at'] as int,
  json: jsonEncode(json),
);

ChatMessage chatMessageFrom(StoredMessage stored) =>
    ChatMessage.fromJson(jsonDecode(stored.json) as Map<String, dynamic>);

/// chat_store's view of the server: GET /conversations/:id/messages by seq.
class ApiMessageSource implements MessageSource {
  ApiMessageSource(this._api, this._userId);

  final ApiService _api;
  final int _userId;

  @override
  Future<SyncPage> after(int conversationId, int afterSeq, int limit) =>
      _page(_api.getMessagesBySeq(conversationId, _userId, afterSeq: afterSeq, limit: limit));

  @override
  Future<SyncPage> before(int conversationId, int beforeSeq, int limit) =>
      _page(_api.getMessagesBySeq(conversationId, _userId, beforeSeq: beforeSeq, limit: limit));

  static Future<SyncPage> _page(Future<({List<Map<String, dynamic>> messages, bool hasMore})> request) async {
    final page = await request;
    return SyncPage([for (final m in page.messages) remoteMessageFrom(m)], hasMore: page.hasMore);
  }
}

/// The signed-in user's chat database: one per user, so a shared browser or
/// a second account never mixes histories (and logout deletes it, see
/// CurrentUserNotifier.logout). Tests override it with an in-memory one.
final chatDatabaseProvider = Provider<ChatDatabase>((ref) {
  final userId = ref.watch(currentUserProvider.select((s) => s.value?.id));
  if (userId == null) throw StateError('no chat database without a signed-in user');
  final db = openChatDatabase('chat_user_$userId');
  ref.onDispose(db.close);
  return db;
});

final messageStoreProvider = Provider<MessageStore>((ref) => MessageStore(ref.watch(chatDatabaseProvider)));

final chatSyncProvider = Provider<ChatSync>((ref) {
  final userId = ref.watch(currentUserProvider.select((s) => s.value?.id));
  if (userId == null) throw StateError('no chat sync without a signed-in user');
  return ChatSync(ref.watch(messageStoreProvider), ApiMessageSource(ref.watch(apiServiceProvider), userId));
});
