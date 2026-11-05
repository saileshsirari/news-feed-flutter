import 'dart:async';

import 'package:chat_store/chat_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/service_providers.dart';
import '../data/services/socket_provider.dart';
import '../models/models.dart';

import '../session/current_user_provider.dart';
import 'chat_outbox.dart';
import 'local/local_chat.dart';
import 'message_sender.dart';

/// Where one of your messages has got to, like WhatsApp's ticks: on the
/// server (✓), on every other member's device (✓✓), read by every other
/// member (blue ✓✓). In a group it takes everyone, so one member who hasn't
/// opened the chat keeps it from going blue.
enum MessageTick { sent, delivered, read }

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
    this.deliveredByUserId = const {},
    this.usernameByUserId = const {},
    this.isLoadingOlder = false,
    this.reachedStart = false,
  });

  final bool isLoading;
  final String? error;
  final bool isSending;

  /// Oldest first: the run of the conversation this device has, newest end.
  final List<ChatMessage> messages;

  /// Fetching the page above the top (you scrolled up).
  final bool isLoadingOlder;

  /// [messages] go back to the conversation's first message.
  final bool reachedStart;

  /// Every participant's read pointer, keyed by userId — the "seen" tick's
  /// data source. Populated once on open (_loadReadStates) and kept current
  /// afterward by read_receipt_updated events, rather than re-fetched on
  /// every change.
  final Map<int, int> readStateByUserId;

  /// Every participant's delivered pointer (at least their read pointer).
  final Map<int, int> deliveredByUserId;

  /// Every participant's name, for "Message info".
  final Map<int, String> usernameByUserId;

  /// The tick for one of [currentUserId]'s messages; null until the
  /// participants are known.
  MessageTick? tickFor(int messageId, {required int currentUserId}) {
    final others = {...readStateByUserId.keys, ...deliveredByUserId.keys}.where((id) => id != currentUserId);
    if (others.isEmpty) return null;
    if (others.every((id) => (readStateByUserId[id] ?? 0) >= messageId)) return MessageTick.read;
    if (others.every((id) => (deliveredByUserId[id] ?? 0) >= messageId)) return MessageTick.delivered;
    return MessageTick.sent;
  }

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
    Map<int, int>? deliveredByUserId,
    Map<int, String>? usernameByUserId,
    bool? isLoadingOlder,
    bool? reachedStart,
  }) {
    return ConversationState(
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _keep) ? this.error : error as String?,
      isSending: isSending ?? this.isSending,
      messages: messages ?? this.messages,
      readStateByUserId: readStateByUserId ?? this.readStateByUserId,
      deliveredByUserId: deliveredByUserId ?? this.deliveredByUserId,
      usernameByUserId: usernameByUserId ?? this.usernameByUserId,
      isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
      reachedStart: reachedStart ?? this.reachedStart,
    );
  }

  static const _keep = Object();
}

/// A single conversation's message thread, local first: what this device
/// already has (chat_store's SQLite) shows at once, even offline; then
/// ChatSync brings in what's new from the server, and the list updates by
/// itself as rows land (it watches the database). Live delivery via the
/// shared AppSocket's message_created events, which carry the message's seq
/// so only what's missing is fetched. Marks read whenever the newest message
/// changes while the chat is open.
///
/// Compose/Android: ≈ `class ConversationViewModel @AssistedInject
/// constructor(@Assisted conversationId: Int, repo: ChatRepository)` that
/// collects a Room `Flow<List<Message>>` and calls `repo.refresh()`.
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
  late MessageStore _store;
  late ChatSync _sync;

  /// The first seq the list shows: the bottom of the newest run.
  int? _from;
  StreamSubscription<List<StoredMessage>>? _messagesSub;
  int _lastMarkedRead = 0;

  @override
  ConversationState build() {
    // ref.read, not watch: the user can't change while a chat is open, and
    // watching would rebuild this dying notifier on logout.
    _currentUserId = ref.read(currentUserProvider).requireValue!.id;
    _store = ref.read(messageStoreProvider(_currentUserId));
    _sync = ref.read(chatSyncProvider(_currentUserId));
    // watch keeps the shared socket alive while this chat is open.
    final socket = ref.watch(socketProvider(_currentUserId));
    final sub = socket.events.listen(_onEvent);
    // Messages with photos/videos finish sending in the outbox, possibly
    // well after you tapped send; show each as it lands.
    ref.listen(chatOutboxProvider(conversationId), (previous, next) {
      for (final message in next.sent.skip(previous?.sent.length ?? 0)) {
        _addSent(message);
      }
    });

    // The list is the newest run, from its first seq up. When scrolling back
    // extends the run downwards, follow it; when no run exists yet, show
    // whatever is stored (e.g. a message you just sent).
    final rangeSub = _store.watchNewestRange(conversationId).listen((range) {
      if (!ref.mounted) return;
      _watchFrom(range?.low ?? 0);
      if (range != null && range.low <= 1 && !state.reachedStart) state = state.copyWith(reachedStart: true);
    });
    ref.onDispose(() {
      sub.cancel();
      rangeSub.cancel();
      _messagesSub?.cancel();
    });

    // Both are async: they only touch `state` after their first await, by
    // which time build() has returned this starting value.
    _syncLatest();
    _loadReadStates();
    return const ConversationState();
  }

  void _watchFrom(int from) {
    if (from == _from) return;
    _from = from;
    _messagesSub?.cancel();
    _messagesSub = _store.watchFrom(conversationId, from).listen((rows) {
      if (!ref.mounted) return;
      final messages = [for (final row in rows) chatMessageFrom(row)];
      state = state.copyWith(messages: messages, isLoading: state.isLoading && messages.isEmpty);
      _markReadIfNewer();
    });
  }

  Future<void> _syncLatest() async {
    try {
      await _sync.syncLatest(conversationId);
      if (!ref.mounted) return;
      state = state.copyWith(isLoading: false, error: null);
      // Photo links in older stored copies may have expired: refresh the
      // ones near the bottom, which is where you'll look first.
      final range = await _store.newestRange(conversationId);
      if (range != null && ref.mounted) {
        await _sync.refreshStale(conversationId, (range.high - 200).clamp(range.low, range.high), range.high);
      }
    } catch (e) {
      if (!ref.mounted) return;
      // Offline with history on the device: just show that.
      state = state.copyWith(isLoading: false, error: state.messages.isEmpty ? 'Couldn\'t load messages: $e' : null);
    }
  }

  /// The page above the oldest message shown (you scrolled to the top).
  Future<void> loadOlder() async {
    if (state.isLoadingOlder || state.reachedStart || state.isLoading) return;
    state = state.copyWith(isLoadingOlder: true);
    try {
      final more = await _sync.loadOlder(conversationId);
      if (!ref.mounted) return;
      state = state.copyWith(isLoadingOlder: false, reachedStart: state.reachedStart || !more);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isLoadingOlder: false, error: 'Couldn\'t load older messages: $e');
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    if (event['type'] == 'reconnected') {
      // Whatever arrived while the socket was down was never delivered:
      // sync, and reload everyone's read pointers.
      _syncLatest();
      _loadReadStates();
      return;
    }
    if (event['conversationId'] != conversationId) return;
    if (event['type'] == 'message_created') {
      // The event carries the seq: fetch only what's missing up to it.
      final seq = event['seq'];
      if (seq is int) {
        _sync.onNewMessage(conversationId, seq).catchError((Object _) {});
      } else {
        _syncLatest();
      }
      return;
    }
    if (event['type'] == 'read_receipt_updated') {
      final userId = event['userId'] as int;
      final read = event['lastReadMessageId'] as int;
      final delivered = event['lastDeliveredMessageId'] as int? ?? read;
      state = state.copyWith(
        readStateByUserId: {...state.readStateByUserId, userId: read},
        deliveredByUserId: {...state.deliveredByUserId, userId: delivered > read ? delivered : read},
      );
    }
  }

  Future<void> _loadReadStates() async {
    try {
      final states = await ref.read(apiServiceProvider).getReadStates(conversationId, _currentUserId);
      // The screen may have closed while we waited; a disposed notifier
      // can't take new state. (The old ChangeNotifier had no such guard.)
      if (!ref.mounted) return;
      state = state.copyWith(
        readStateByUserId: {...state.readStateByUserId, for (final s in states) s.userId: s.lastReadMessageId},
        deliveredByUserId: {...state.deliveredByUserId, for (final s in states) s.userId: s.lastDeliveredMessageId},
        usernameByUserId: {for (final s in states) s.userId: s.username},
      );
    } catch (_) {
      // Best-effort — the conversation still works with no "seen" indicator.
    }
  }

  /// Opening a chat, or a new message arriving while it's open, is reading.
  void _markReadIfNewer() {
    if (state.messages.isEmpty) return;
    final newest = state.messages.last.id;
    if (newest <= _lastMarkedRead) return;
    _lastMarkedRead = newest;
    ref
        .read(apiServiceProvider)
        .markRead(conversationId, userId: _currentUserId, lastReadMessageId: newest)
        // Best-effort — an unread badge staying stale is not worth an error.
        .catchError((Object _) {});
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
      await _addSent(message);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isSending: false, error: 'Couldn\'t send: $e');
    }
  }

  /// Your own sent message, from here or the outbox: stored at once so it
  /// shows, then anything sent by others just before it is fetched too.
  Future<void> _addSent(ChatMessage message) async {
    if (message.seq <= 0 || message.json.isEmpty) return; // an older server
    try {
      await _store.upsertAll([remoteMessageFrom(message.json)]);
      await _sync.onNewMessage(conversationId, message.seq);
    } catch (_) {
      // Shown anyway once the next sync runs.
    }
  }
}

/// One notifier per open conversation.
///   - `.autoDispose`: cleared when ConversationScreen closes
///     (≈ ViewModel cleared when the screen leaves the back stack)
///   - `.family<..., int>`: keyed by conversation id, so
///     `ref.watch(conversationProvider(42))` ≈ `hiltViewModel(key = "42")`
final conversationProvider = NotifierProvider.autoDispose.family<ConversationNotifier, ConversationState, int>(
  ConversationNotifier.new,
);
