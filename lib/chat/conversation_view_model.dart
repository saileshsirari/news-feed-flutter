import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../network/api_client.dart';
import '../network/app_socket.dart';

/// A single conversation's message thread — history via GET
/// /conversations/:id/messages, live delivery via the shared AppSocket's
/// message_created events (see chatConsumer.ts for the server side of that
/// push). Marks read whenever the newest message changes, same "opened it,
/// so mark read" trigger a real app would use.
class ConversationViewModel extends ChangeNotifier {
  final ApiClient _api;
  final int conversationId;
  final int currentUserId;
  final AppSocket? _socket;
  StreamSubscription<Map<String, dynamic>>? _socketSub;

  ConversationViewModel(
    this._api, {
    required this.conversationId,
    required this.currentUserId,
    AppSocket? socket,
  }) : _socket = socket {
    _load();
    _loadReadStates();
    _socketSub = _socket?.events.listen(_onEvent);
  }

  bool isLoading = true;
  String? error;
  bool isSending = false;
  List<ChatMessage> messages = [];

  /// Every participant's read pointer, keyed by userId — the "seen" tick's
  /// data source. Populated once on open (_loadReadStates) and kept current
  /// afterward by read_receipt_updated events, rather than re-fetched on
  /// every change.
  final Map<int, int> readStateByUserId = {};

  void _onEvent(Map<String, dynamic> event) {
    if (event['conversationId'] != conversationId) return;
    if (event['type'] == 'message_created') {
      // The push only ever carries an id, same "go fetch the real thing"
      // pattern as the feed's realtime ping — reload rather than trust
      // whatever shape happens to be in the event payload.
      _load(markReadAfter: true);
      return;
    }
    if (event['type'] == 'read_receipt_updated') {
      readStateByUserId[event['userId'] as int] = event['lastReadMessageId'] as int;
      notifyListeners();
    }
  }

  Future<void> _loadReadStates() async {
    try {
      final states = await _api.getReadStates(conversationId, currentUserId);
      for (final state in states) {
        readStateByUserId[state.userId] = state.lastReadMessageId;
      }
      notifyListeners();
    } catch (_) {
      // Best-effort — the conversation still works with no "seen" indicator.
    }
  }

  /// True once every *other* participant has read up to [messageId] — the
  /// "Seen" tick shown under the current user's own last message. Returns
  /// false (not "unknown") before the initial read-state fetch completes, so
  /// the UI simply shows nothing rather than a misleading tick.
  bool isReadByOthers(int messageId) {
    final others = readStateByUserId.keys.where((id) => id != currentUserId);
    if (others.isEmpty) return false;
    return others.every((id) => (readStateByUserId[id] ?? 0) >= messageId);
  }

  Future<void> _load({bool markReadAfter = false}) async {
    isLoading = messages.isEmpty;
    error = null;
    notifyListeners();
    try {
      final page = await _api.getMessages(conversationId, currentUserId);
      // Server returns newest-first; a chat UI wants oldest-first (reading
      // top to bottom), so reverse once here rather than re-querying.
      messages = page.messages.reversed.toList();
      isLoading = false;
      notifyListeners();
      if (markReadAfter && messages.isNotEmpty) _markRead();
    } catch (e) {
      isLoading = false;
      error = 'Couldn\'t load messages: $e';
      notifyListeners();
    }
  }

  Future<void> _markRead() async {
    if (messages.isEmpty) return;
    try {
      await _api.markRead(conversationId, userId: currentUserId, lastReadMessageId: messages.last.id);
    } catch (_) {
      // Best-effort — an unread badge staying stale is not worth surfacing an error for.
    }
  }

  Future<void> send(String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    isSending = true;
    notifyListeners();
    try {
      final message = await _api.sendMessage(conversationId, senderId: currentUserId, body: trimmed);
      messages = [...messages, message];
      isSending = false;
      notifyListeners();
      _markRead();
    } catch (e) {
      isSending = false;
      error = 'Couldn\'t send: $e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    super.dispose();
  }
}
