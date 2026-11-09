import 'dart:convert';

import 'package:chat_store/chat_store.dart';

/// The quick choices when you long-press a message, as in WhatsApp; ➕ opens
/// every emoji. Emojis are plain Unicode text, drawn by the device's own
/// emoji font.
const quickReactions = ['❤️', '😂', '😮', '😢', '🙏', '👍'];

/// [messageJson] with [userId]'s reaction set to [emoji], or removed (null):
/// one reaction per person, a new one replaces theirs, empty groups go.
Map<String, dynamic> withReaction(Map<String, dynamic> messageJson, int userId, String? emoji) {
  final groups = <({String emoji, List<int> userIds})>[
    for (final r in messageJson['reactions'] as List? ?? const [])
      (
        emoji: (r as Map)['emoji'] as String,
        userIds: [for (final id in r['user_ids'] as List) id as int]..remove(userId),
      ),
  ];
  if (emoji != null) {
    final existing = groups.indexWhere((g) => g.emoji == emoji);
    if (existing >= 0) {
      groups[existing].userIds.add(userId);
    } else {
      groups.add((emoji: emoji, userIds: [userId]));
    }
  }
  return {
    ...messageJson,
    'reactions': [
      for (final g in groups)
        if (g.userIds.isNotEmpty) {'emoji': g.emoji, 'user_ids': g.userIds},
    ],
  };
}

/// Applies a reaction change to this device's stored copy of the message
/// (the chat screen redraws from the store by itself). Nothing happens if
/// this device doesn't have that message.
Future<void> applyReaction(
  MessageStore store, {
  required int conversationId,
  required int messageId,
  required int userId,
  required String? emoji,
}) async {
  final stored = await store.byMessageId(conversationId, messageId);
  if (stored == null) return;
  final json = withReaction(jsonDecode(stored.json) as Map<String, dynamic>, userId, emoji);
  await store.updateJson(conversationId, messageId, jsonEncode(json));
}
