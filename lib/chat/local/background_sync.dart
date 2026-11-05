import 'dart:async';

import 'package:chat_store/chat_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/api_service.dart';
import '../../data/services/service_providers.dart';
import '../../data/services/socket_provider.dart';
import '../../session/current_user_provider.dart';
import 'local_chat.dart';

/// While the app is open and someone is signed in: new messages in *any*
/// chat are synced to this device as they're sent, and the server is told
/// they arrived (the sender's ✓✓ "delivered"), like WhatsApp. Chats then
/// open with their new messages already there.
///
/// Catches up on start and after reconnecting too: whatever came in while
/// the app was closed or offline. (With the app closed, nothing arrives
/// until push notifications wake it, so messages stay at one ✓ until then.)
class ChatBackgroundSync {
  ChatBackgroundSync({
    required this.userId,
    required this.api,
    required this.sync,
    required this.store,
    required Stream<Map<String, dynamic>> events,
  }) {
    _events = events.listen(_onEvent);
    unawaited(catchUpAll());
  }

  final int userId;
  final ApiService api;
  final ChatSync sync;
  final MessageStore store;
  late final StreamSubscription<Map<String, dynamic>> _events;

  /// The newest message id already reported per conversation, so the same
  /// one isn't reported twice.
  final _reported = <int, int>{};

  void dispose() => _events.cancel();

  void _onEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'message_created':
        final conversationId = event['conversationId'];
        final seq = event['seq'];
        if (conversationId is! int || seq is! int || event['senderId'] == userId) return;
        unawaited(
          _guard(() async {
            await sync.onNewMessage(conversationId, seq);
            await _reportDelivered(conversationId);
          }),
        );
      case 'reconnected':
        unawaited(catchUpAll());
    }
  }

  /// Every chat the server has news in that this device doesn't.
  Future<void> catchUpAll() => _guard(() async {
    for (final conversation in await api.listConversations(userId)) {
      if (conversation.lastSeq == 0) continue;
      final newest = await store.newestRange(conversation.id);
      if (newest != null && newest.high >= conversation.lastSeq) continue;
      await sync.syncLatest(conversation.id);
      await _reportDelivered(conversation.id);
    }
  });

  Future<void> _reportDelivered(int conversationId) async {
    final newest = await store.newestRange(conversationId);
    if (newest == null) return;
    final rows = await store.watchFrom(conversationId, newest.high).first;
    if (rows.isEmpty) return;
    final messageId = rows.last.messageId;
    if ((_reported[conversationId] ?? 0) >= messageId) return;
    _reported[conversationId] = messageId;
    await api.markDelivered(conversationId, userId: userId, lastDeliveredMessageId: messageId);
  }

  /// Best effort: a failed sync or report is retried on the next event or
  /// reconnect; it must never break the app.
  static Future<void> _guard(Future<void> Function() work) async {
    try {
      await work();
    } on Object catch (e) {
      debugPrint('[chat-sync] background sync failed: $e');
    }
  }
}

/// Alive while HomeScreen is (watched there): signed in, app open.
final chatBackgroundSyncProvider = Provider.autoDispose<ChatBackgroundSync?>((ref) {
  final userId = ref.watch(currentUserProvider.select((s) => s.value?.id));
  if (userId == null) return null;
  final background = ChatBackgroundSync(
    userId: userId,
    api: ref.watch(apiServiceProvider),
    sync: ref.watch(chatSyncProvider),
    store: ref.watch(messageStoreProvider),
    events: ref.watch(socketProvider(userId)).events,
  );
  ref.onDispose(background.dispose);
  return background;
});
