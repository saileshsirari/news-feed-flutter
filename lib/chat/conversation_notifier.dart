import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/service_providers.dart';
import '../data/services/socket_provider.dart';
import '../models/models.dart';
import '../session/current_user_provider.dart';
import 'chat_outbox.dart';
import 'message_sender.dart';

/// Everything ConversationScreen draws, as one immutable value.
///
/// Riverpod only notices `state = newValue`, never a field changing inside
/// the old value, so instead of mutable fields + notifyListeners() every
/// change builds a new ConversationState with copyWith.
///
/// Compose/Android: ≈ `data class ConversationUiState(...)` held in a
/// `MutableStateFlow`, updated with `_state.update { it.copy(...) }`.
class ConversationState {
  const ConversationState({
    this.isLoading = true,
    this.error,
    this.isSending = false,
    this.messages = const [],
    this.readStateByUserId = const {},
  });

  final bool isLoading;
  final String? error;
  final bool isSending;
  final List<ChatMessage> messages;

  /// Every participant's read pointer, keyed by userId — the "seen" tick's
  /// data source. Populated once on open (_loadReadStates) and kept current
  /// afterward by read_receipt_updated events, rather than re-fetched on
  /// every change.
  final Map<int, int> readStateByUserId;

  /// True once every *other* participant has read up to [messageId] — the
  /// "Seen" tick shown under the current user's own last message. Returns
  /// false (not "unknown") before the initial read-state fetch completes, so
  /// the UI simply shows nothing rather than a misleading tick.
  bool isReadByOthers(int messageId, {required int currentUserId}) {
    final others = readStateByUserId.keys.where((id) => id != currentUserId);
    if (others.isEmpty) return false;
    return others.every((id) => (readStateByUserId[id] ?? 0) >= messageId);
  }

  /// [error] uses a sentinel so `copyWith(error: null)` can clear it
  /// (a plain `String? error` parameter couldn't tell "clear" from "keep").
  ConversationState copyWith({
    bool? isLoading,
    Object? error = _keep,
    bool? isSending,
    List<ChatMessage>? messages,
    Map<int, int>? readStateByUserId,
  }) {
    return ConversationState(
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _keep) ? this.error : error as String?,
      isSending: isSending ?? this.isSending,
      messages: messages ?? this.messages,
      readStateByUserId: readStateByUserId ?? this.readStateByUserId,
    );
  }

  static const _keep = Object();
}

/// A single conversation's message thread — history via GET
/// /conversations/:id/messages, live delivery via the shared AppSocket's
/// message_created events (see chatConsumer.ts for the server side of that
/// push). Marks read whenever the newest message changes, same "opened it,
/// so mark read" trigger a real app would use.
///
/// Compose/Android: ≈ `class ConversationViewModel @AssistedInject
/// constructor(@Assisted conversationId: Int, api: ApiService)`.
///   - `Notifier<ConversationState>` ≈ ViewModel with `StateFlow<UiState>`
///   - `build()`                     ≈ `init { }`: first state + start loading
///   - `state = state.copyWith(...)` ≈ `_state.update { it.copy(...) }`,
///                                     replaces every notifyListeners()
///   - `ref.onDispose(...)`          ≈ `onCleared()`
///   - `ref.mounted`                 ≈ checking `viewModelScope.isActive`
///                                     (here: is the screen still open?)
class ConversationNotifier extends Notifier<ConversationState> {
  ConversationNotifier(this.conversationId);

  /// The family argument: `conversationProvider(42)` makes a notifier with
  /// conversationId 42.
  final int conversationId;
  late int _currentUserId;

  @override
  ConversationState build() {
    // ref.read, not watch: the user can't change while a chat is open, and
    // watching would rebuild this dying notifier on logout.
    _currentUserId = ref.read(currentUserProvider).requireValue!.id;
    // watch keeps the shared socket alive while this chat is open.
    final socket = ref.watch(socketProvider(_currentUserId));
    final sub = socket.events.listen(_onEvent);
    ref.onDispose(sub.cancel);
    // Messages with photos/videos finish sending in the outbox, possibly
    // well after you tapped send; show each as it lands.
    ref.listen(chatOutboxProvider(conversationId), (previous, next) {
      for (final message in next.sent.skip(previous?.sent.length ?? 0)) {
        _addSent(message);
      }
    });

    // Both are async: they only touch `state` after their first await, by
    // which time build() has returned this starting value.
    _fetchMessages();
    _loadReadStates();
    return const ConversationState();
  }

  void _onEvent(Map<String, dynamic> event) {
    if (event['type'] == 'reconnected') {
      // Whatever arrived while the socket was down was never delivered:
      // reload both the messages and everyone's read pointers.
      _fetchMessages(markReadAfter: true);
      _loadReadStates();
      return;
    }
    if (event['conversationId'] != conversationId) return;
    if (event['type'] == 'message_created') {
      // The push only ever carries an id, same "go fetch the real thing"
      // pattern as the feed's realtime ping — reload rather than trust
      // whatever shape happens to be in the event payload.
      state = state.copyWith(isLoading: state.messages.isEmpty, error: null);
      _fetchMessages(markReadAfter: true);
      return;
    }
    if (event['type'] == 'read_receipt_updated') {
      state = state.copyWith(readStateByUserId: {
        ...state.readStateByUserId,
        event['userId'] as int: event['lastReadMessageId'] as int,
      });
    }
  }

  Future<void> _loadReadStates() async {
    try {
      final states = await ref.read(apiServiceProvider).getReadStates(conversationId, _currentUserId);
      // The screen may have closed while we waited; a disposed notifier
      // can't take new state. (The old ChangeNotifier had no such guard.)
      if (!ref.mounted) return;
      state = state.copyWith(readStateByUserId: {
        ...state.readStateByUserId,
        for (final s in states) s.userId: s.lastReadMessageId,
      });
    } catch (_) {
      // Best-effort — the conversation still works with no "seen" indicator.
    }
  }

  Future<void> _fetchMessages({bool markReadAfter = false}) async {
    try {
      final page = await ref.read(apiServiceProvider).getMessages(conversationId, _currentUserId);
      if (!ref.mounted) return;
      // Server returns newest-first; a chat UI wants oldest-first (reading
      // top to bottom), so reverse once here rather than re-querying.
      state = state.copyWith(messages: page.messages.reversed.toList(), isLoading: false);
      if (markReadAfter && state.messages.isNotEmpty) _markRead();
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isLoading: false, error: 'Couldn\'t load messages: $e');
    }
  }

  Future<void> _markRead() async {
    if (state.messages.isEmpty) return;
    try {
      await ref
          .read(apiServiceProvider)
          .markRead(conversationId, userId: _currentUserId, lastReadMessageId: state.messages.last.id);
    } catch (_) {
      // Best-effort — an unread badge staying stale is not worth surfacing an error for.
    }
  }

  /// Sends text right away (retrying once on a dropped connection, see
  /// sendWithOneRetry). Messages with photos or videos go through
  /// ChatOutboxNotifier instead, which waits for their uploads.
  Future<void> send(String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(isSending: true);
    try {
      final message = await sendWithOneRetry(
        ref.read(apiServiceProvider),
        conversationId,
        senderId: _currentUserId,
        body: trimmed,
        clientMessageId: newClientMessageId(_currentUserId),
      );
      if (!ref.mounted) return;
      state = state.copyWith(isSending: false);
      _addSent(message);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isSending: false, error: 'Couldn\'t send: $e');
    }
  }

  /// Your own sent message, from here or the outbox: added at once (the
  /// socket only announces other people's messages), unless a reload got
  /// there first.
  void _addSent(ChatMessage message) {
    if (state.messages.any((m) => m.id == message.id)) return;
    state = state.copyWith(messages: [...state.messages, message]);
    _markRead();
  }
}

/// One notifier per open conversation.
///   - `.autoDispose`: cleared when ConversationScreen closes
///     (≈ ViewModel cleared when the screen leaves the back stack)
///   - `.family<..., int>`: keyed by conversation id, so
///     `ref.watch(conversationProvider(42))` ≈ `hiltViewModel(key = "42")`
final conversationProvider =
    NotifierProvider.autoDispose.family<ConversationNotifier, ConversationState, int>(ConversationNotifier.new);
