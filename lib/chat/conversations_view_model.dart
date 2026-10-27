import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../network/api_client.dart';
import '../network/app_socket.dart';

/// The "Chat" tab's primary view: conversations you're already in, most
/// recently active first (server-sorted) — as opposed to contacts_view_model,
/// which lists every user you *could* start a chat with. Refreshes on three
/// socket events: conversations_changed (see chatConsumer.ts's
/// applyParticipantChange — a new chat/group you were just added to),
/// message_created (someone sent a message in one of your conversations —
/// moves it to the top with a fresh preview and unread count) and
/// read_receipt_updated (irrelevant to what's shown here, but cheap enough to
/// just reload on too rather than special-case). All three carry only ids,
/// same "don't trust the payload shape, go re-fetch" pattern as
/// ConversationViewModel — a full reload is simplest and correct at this
/// scale. Note the fanout excludes whoever *caused* the event (see
/// publishToOtherParticipants), so your own sent messages and your own
/// read-marking never arrive here as a push — conversations_list_screen.dart
/// covers that by reloading when you pop back from a conversation instead.
class ConversationsViewModel extends ChangeNotifier {
  final ApiClient _api;
  final int currentUserId;
  final AppSocket? _socket;
  StreamSubscription<Map<String, dynamic>>? _socketSub;

  static const _reloadTriggers = {'conversations_changed', 'message_created', 'read_receipt_updated'};

  ConversationsViewModel(this._api, {required this.currentUserId, AppSocket? socket}) : _socket = socket {
    load();
    _socketSub = _socket?.events.listen((event) {
      if (_reloadTriggers.contains(event['type'])) load();
    });
  }

  bool isLoading = false;
  String? error;
  List<ConversationSummary> conversations = [];

  Future<void> load() async {
    isLoading = conversations.isEmpty;
    error = null;
    notifyListeners();
    try {
      conversations = await _api.listConversations(currentUserId);
      isLoading = false;
      notifyListeners();
    } catch (e) {
      isLoading = false;
      error = 'Couldn\'t load conversations: $e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    super.dispose();
  }
}
