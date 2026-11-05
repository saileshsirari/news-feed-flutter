import 'dart:convert';

import 'package:chat_store/testing.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:http/http.dart' as http;
import 'package:news_feed_flutter/chat/local/local_chat.dart';

/// The chat database in memory, for a test's ProviderContainer/ProviderScope.
List<Override> localChatOverrides() => [
  chatDatabaseProvider.overrideWith((ref, userId) {
    final db = inMemoryChatDatabase();
    ref.onDispose(db.close);
    return db;
  }),
];

/// Answers GET /conversations/:id/messages?afterSeq=|beforeSeq= like the
/// server, from [messages] (each with a 'seq', in any order).
http.Response answerMessagesBySeq(http.Request request, List<Map<String, dynamic>> messages) {
  final query = request.url.queryParameters;
  final limit = int.parse(query['limit'] ?? '50');
  final sorted = [...messages]..sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int));
  final List<Map<String, dynamic>> candidates;
  if (query['afterSeq'] != null) {
    final after = int.parse(query['afterSeq']!);
    candidates = sorted.where((m) => (m['seq'] as int) > after).toList();
  } else {
    final before = int.parse(query['beforeSeq'] ?? '9007199254740991');
    candidates = sorted.where((m) => (m['seq'] as int) < before).toList().reversed.toList();
  }
  return http.Response(
    jsonEncode({'messages': candidates.take(limit).toList(), 'hasMore': candidates.length > limit}),
    200,
  );
}
