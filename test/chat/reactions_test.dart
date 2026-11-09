import 'dart:convert';

import 'package:chat_store/chat_store.dart';
import 'package:chat_store/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:news_feed_flutter/chat/local/local_chat.dart';
import 'package:news_feed_flutter/chat/reactions.dart';
import 'package:news_feed_flutter/models/models.dart';

Map<String, dynamic> message({List<Map<String, dynamic>> reactions = const []}) => {
      'id': 50,
      'conversation_id': 5,
      'seq': 1,
      'sender_id': 2,
      'body': 'party at 8',
      'created_at': 0,
      'sender_username': 'ann',
      'reactions': reactions,
    };

/// [[emoji, [user ids]], ...]: lists, since records holding lists don't compare by content.
List<List<Object>> reactionsOf(Map<String, dynamic> json) =>
    [for (final r in ChatMessage.fromJson(json).reactions) [r.emoji, r.userIds]];

void main() {
  group('withReaction', () {
    test('adds, groups the same emoji, and keeps the order they came in', () {
      var json = withReaction(message(), 1, '❤️');
      json = withReaction(json, 2, '😂');
      json = withReaction(json, 3, '❤️');
      expect(reactionsOf(json), [['❤️', [1, 3]], ['😂', [2]]]);
    });

    test('one per person: a new emoji replaces theirs; null removes it; empty groups go', () {
      var json = withReaction(message(), 1, '❤️');
      json = withReaction(json, 1, '👍');
      expect(reactionsOf(json), [['👍', [1]]]);
      json = withReaction(json, 1, null);
      expect(reactionsOf(json), isEmpty);
    });

    test('leaves everything else about the message alone', () {
      final json = withReaction(message(), 1, '🙏');
      expect(json['body'], 'party at 8');
      expect(json['seq'], 1);
    });
  });

  test('applyReaction updates the stored copy, and ignores messages not here', () async {
    final db = inMemoryChatDatabase();
    addTearDown(db.close);
    final store = MessageStore(db);
    await store.upsertAll([remoteMessageFrom(message())]);

    await applyReaction(store, conversationId: 5, messageId: 50, userId: 7, emoji: '😮');
    final stored = await store.byMessageId(5, 50);
    expect(reactionsOf(jsonDecode(stored!.json) as Map<String, dynamic>), [['😮', [7]]]);

    await applyReaction(store, conversationId: 5, messageId: 999, userId: 7, emoji: '😮'); // no error
  });
}
