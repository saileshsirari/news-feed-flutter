import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../data/services/api_service.dart';

/// The "everyone you can message" list — every user is a valid chat target
/// here, celebrity or not (unlike the feed, which is follow-scoped). Tapping
/// a contact normally starts/reopens a 1:1 (see chatService.startConversation's
/// idempotent-for-pairs behavior on the server). Toggling selection mode
/// turns the same list into a multi-pick for group creation instead of a
/// separate screen — same list either way, matching how it was asked for.
class ContactsViewModel extends ChangeNotifier {
  final ApiService _api;
  final int _currentUserId;

  ContactsViewModel(this._api, this._currentUserId) {
    load();
  }

  bool isLoading = false;
  String? error;
  List<User> contacts = [];

  bool selectionMode = false;
  final Set<int> selectedUserIds = {};

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final users = await _api.listUsers();
      contacts = users.where((u) => u.id != _currentUserId).toList();
      isLoading = false;
      notifyListeners();
    } catch (e) {
      isLoading = false;
      error = 'Couldn\'t load contacts: $e';
      notifyListeners();
    }
  }

  /// Starts (or reopens) a 1:1 conversation with [other] and returns its id.
  Future<int> openDirectConversation(User other) async {
    final conversation = await _api.createConversation(
      participantIds: [_currentUserId, other.id],
      isGroup: false,
    );
    return conversation.id;
  }

  void toggleSelectionMode() {
    selectionMode = !selectionMode;
    selectedUserIds.clear();
    notifyListeners();
  }

  void toggleSelected(int userId) {
    if (!selectedUserIds.remove(userId)) selectedUserIds.add(userId);
    notifyListeners();
  }

  List<User> get selectedUsers => contacts.where((c) => selectedUserIds.contains(c.id)).toList();

  /// Groups always create fresh — unlike the 1:1 case, there's no sensible
  /// "the same group" to reuse, since membership is chosen explicitly each
  /// time. [name] falls back to a comma-joined list of usernames when left
  /// blank, so the conversation screen always has something to show as its
  /// title even for an unnamed group.
  Future<Conversation> createGroup(String? name) async {
    final trimmedName = name?.trim();
    final fallbackName = selectedUsers.map((u) => u.username).join(', ');
    final conversation = await _api.createConversation(
      participantIds: [_currentUserId, ...selectedUserIds],
      isGroup: true,
      name: (trimmedName == null || trimmedName.isEmpty) ? fallbackName : trimmedName,
    );
    selectionMode = false;
    selectedUserIds.clear();
    notifyListeners();
    return conversation;
  }
}
