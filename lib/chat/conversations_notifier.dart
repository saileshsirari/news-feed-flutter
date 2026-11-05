import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/service_providers.dart';
import '../data/services/socket_provider.dart';
import '../models/models.dart';
import '../session/current_user_provider.dart';

/// Everything the Chat tab draws, as one immutable value (see
/// ConversationState for why: Riverpod only notices `state = newValue`).
///
/// Compose/Android: ≈ `data class ConversationsUiState(...)`.
class ConversationsState {
  const ConversationsState({this.isLoading = true, this.error, this.conversations = const []});

  final bool isLoading;
  final String? error;
  final List<ConversationSummary> conversations;

  /// [error] uses a sentinel so `copyWith(error: null)` can clear it.
  ConversationsState copyWith({bool? isLoading, Object? error = _keep, List<ConversationSummary>? conversations}) {
    return ConversationsState(
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _keep) ? this.error : error as String?,
      conversations: conversations ?? this.conversations,
    );
  }

  static const _keep = Object();
}

/// The "Chat" tab's primary view: conversations you're already in, most
/// recently active first (server-sorted) — as opposed to contacts_notifier,
/// which lists every user you *could* start a chat with. Refreshes on three
/// socket events: conversations_changed (see chatConsumer.ts's
/// applyParticipantChange — a new chat/group you were just added to),
/// message_created (someone sent a message in one of your conversations —
/// moves it to the top with a fresh preview and unread count) and
/// read_receipt_updated (irrelevant to what's shown here, but cheap enough to
/// just reload on too rather than special-case). All three carry only ids,
/// same "don't trust the payload shape, go re-fetch" pattern as
/// ConversationNotifier — a full reload is simplest and correct at this
/// scale. Events reach every participant, including whoever caused them,
/// so your own sends and read-marking from another device (your phone while
/// you're in the browser) update this list too; conversations_list_screen.dart
/// also reloads when you pop back from a conversation.
///
/// Compose/Android: ≈ `@HiltViewModel class ConversationsViewModel` with a
/// `StateFlow<ConversationsUiState>` and a public `load()`. No family here:
/// there's only ever one Chat tab, so no id is needed to tell instances apart.
class ConversationsNotifier extends Notifier<ConversationsState> {
  // 'reconnected' (see AppSocket): catch up on anything missed while the
  // socket was down.
  static const _reloadTriggers = {'conversations_changed', 'message_created', 'read_receipt_updated', 'reconnected'};

  late int _currentUserId;

  @override
  ConversationsState build() {
    // ref.read, not watch: the user can't change while the Chat tab exists
    // (see ConversationNotifier.build).
    _currentUserId = ref.read(currentUserProvider).requireValue!.id;
    final sub = ref.watch(socketProvider(_currentUserId)).events.listen((event) {
      if (_reloadTriggers.contains(event['type'])) load();
    });
    ref.onDispose(sub.cancel);

    // Async: only touches `state` after its first await, by which time
    // build() has returned the starting value (isLoading: true).
    _fetch();
    return const ConversationsState();
  }

  /// Pull-to-refresh, the refresh button, and returning from a chat.
  Future<void> load() async {
    state = state.copyWith(isLoading: state.conversations.isEmpty, error: null);
    await _fetch();
  }

  Future<void> _fetch() async {
    try {
      final conversations = await ref.read(apiServiceProvider).listConversations(_currentUserId);
      if (!ref.mounted) return;
      state = state.copyWith(conversations: conversations, isLoading: false);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isLoading: false, error: 'Couldn\'t load conversations: $e');
    }
  }
}

/// autoDispose: cleared on logout, when the Chat tab (and HomeScreen) goes
/// away. ≈ the ViewModel being cleared with its screen.
final conversationsProvider =
    NotifierProvider.autoDispose<ConversationsNotifier, ConversationsState>(ConversationsNotifier.new);
