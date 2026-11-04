import 'dart:math';

import 'package:flutter/foundation.dart';
import '../data/services/api_service.dart';
import '../models/models.dart';

/// How long a send waits before its one retry; tests shorten it.
@visibleForTesting
Duration retryDelay = const Duration(seconds: 1);

/// A new id for one send: unique per user without asking the server, and
/// only letters, digits and dashes, as the server requires.
String newClientMessageId(int userId) =>
    '$userId-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(_randomMax).toRadixString(36)}';

/// A literal, not `1 << 32`: on web, Dart's shifts are 32-bit JavaScript
/// ones, so `1 << 32` is 0 there and `nextInt(0)` throws — every chat send
/// in the browser failed that way.
const _randomMax = 0x7fffffff;

/// Sends one message, retrying once if the connection fails. The retry
/// reuses [clientMessageId], so if the first attempt did reach the server
/// (only its reply was lost), the server returns that message rather than
/// posting it twice. A refusal from the server isn't retried.
///
/// Shared by plain text sends (ConversationNotifier) and messages with
/// photos or videos (ChatOutboxNotifier).
Future<ChatMessage> sendWithOneRetry(
  ApiService api,
  int conversationId, {
  required int senderId,
  required String body,
  required String clientMessageId,
  List<int> mediaIds = const [],
}) async {
  Future<ChatMessage> attempt() => api.sendMessage(
        conversationId,
        senderId: senderId,
        body: body,
        clientMessageId: clientMessageId,
        mediaIds: mediaIds,
      );
  try {
    return await attempt();
  } on ApiException {
    rethrow;
  } catch (_) {
    await Future<void>.delayed(retryDelay);
    return attempt();
  }
}
