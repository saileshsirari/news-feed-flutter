import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/service_providers.dart';
import '../models/models.dart';
import '../session/current_user_provider.dart';

/// Everything ContactsScreen draws, as one immutable value — including
/// pure UI state (selection mode, which rows are checked). It lives here
/// rather than in the widget because the app bar, every row and the
/// create-group dialog all read it.
///
/// Compose/Android: ≈ `data class ContactsUiState(...)`; the selection
/// fields are what you'd otherwise keep in the ViewModel as
/// `selectedIds: Set<Int>` so rotation doesn't lose your picks.
class ContactsState {
  const ContactsState({
    this.isLoading = true,
    this.error,
    this.contacts = const [],
    this.selectionMode = false,
    this.selectedUserIds = const {},
  });

  final bool isLoading;
  final String? error;
  final List<User> contacts;
  final bool selectionMode;
  final Set<int> selectedUserIds;

  List<User> get selectedUsers => contacts.where((c) => selectedUserIds.contains(c.id)).toList();

  /// [error] uses a sentinel so `copyWith(error: null)` can clear it.
  ContactsState copyWith({
    bool? isLoading,
    Object? error = _keep,
    List<User>? contacts,
    bool? selectionMode,
    Set<int>? selectedUserIds,
  }) {
    return ContactsState(
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _keep) ? this.error : error as String?,
      contacts: contacts ?? this.contacts,
      selectionMode: selectionMode ?? this.selectionMode,
      selectedUserIds: selectedUserIds ?? this.selectedUserIds,
    );
  }

  static const _keep = Object();
}

/// The "everyone you can message" list — every user is a valid chat target
/// here, celebrity or not (unlike the feed, which is follow-scoped). Tapping
/// a contact normally starts/reopens a 1:1 (see chatService.startConversation's
/// idempotent-for-pairs behavior on the server). Toggling selection mode
/// turns the same list into a multi-pick for group creation instead of a
/// separate screen — same list either way, matching how it was asked for.
///
/// Compose/Android: ≈ `@HiltViewModel class ContactsViewModel`. The two
/// `Future<...>`-returning methods are like `suspend fun`s the screen calls
/// from a click handler (`scope.launch { val id = vm.open(user); navigate(id) }`):
/// the result drives navigation, so it's returned, not put in state.
class ContactsNotifier extends Notifier<ContactsState> {
  late int _currentUserId;

  @override
  ContactsState build() {
    // ref.read, not watch: see ConversationNotifier.build.
    _currentUserId = ref.read(currentUserProvider).requireValue!.id;
    _fetch();
    return const ContactsState();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    await _fetch();
  }

  Future<void> _fetch() async {
    try {
      final users = await ref.read(apiServiceProvider).listUsers();
      if (!ref.mounted) return;
      state = state.copyWith(contacts: users.where((u) => u.id != _currentUserId).toList(), isLoading: false);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isLoading: false, error: 'Couldn\'t load contacts: $e');
    }
  }

  /// Starts (or reopens) a 1:1 conversation with [other] and returns its id.
  Future<int> openDirectConversation(User other) async {
    final conversation = await ref.read(apiServiceProvider).createConversation(
          participantIds: [_currentUserId, other.id],
          isGroup: false,
        );
    return conversation.id;
  }

  void toggleSelectionMode() {
    state = state.copyWith(selectionMode: !state.selectionMode, selectedUserIds: const {});
  }

  void toggleSelected(int userId) {
    final selected = state.selectedUserIds;
    // A new Set, never selected.add(): the old one is part of the old state
    // and must stay unchanged, or Riverpod can't tell anything changed.
    state = state.copyWith(
      selectedUserIds: selected.contains(userId) ? ({...selected}..remove(userId)) : {...selected, userId},
    );
  }

  /// Groups always create fresh — unlike the 1:1 case, there's no sensible
  /// "the same group" to reuse, since membership is chosen explicitly each
  /// time. [name] falls back to a comma-joined list of usernames when left
  /// blank, so the conversation screen always has something to show as its
  /// title even for an unnamed group.
  Future<Conversation> createGroup(String? name) async {
    final trimmedName = name?.trim();
    final fallbackName = state.selectedUsers.map((u) => u.username).join(', ');
    final conversation = await ref.read(apiServiceProvider).createConversation(
          participantIds: [_currentUserId, ...state.selectedUserIds],
          isGroup: true,
          name: (trimmedName == null || trimmedName.isEmpty) ? fallbackName : trimmedName,
        );
    if (ref.mounted) state = state.copyWith(selectionMode: false, selectedUserIds: const {});
    return conversation;
  }
}

/// autoDispose: cleared when ContactsScreen is replaced by the conversation
/// it opened, or popped.
final contactsProvider = NotifierProvider.autoDispose<ContactsNotifier, ContactsState>(ContactsNotifier.new);
