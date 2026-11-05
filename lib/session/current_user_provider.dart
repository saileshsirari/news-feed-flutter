import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../chat/local/local_chat.dart';
import '../data/services/api_service.dart';
import '../data/services/service_providers.dart';
import '../models/models.dart';
import 'device_registration.dart';
import 'user_session.dart';

/// Who's logged in: loading while the saved session is read at startup,
/// then null (logged out) or the user. This used to live inside
/// FeedViewModel, so chat and calls had to reach into the feed's view model
/// to learn the user id; now everything watches this instead.
///
/// Compose/Android equivalent: an app-wide (activity-scoped) ViewModel
///
///     class SessionViewModel : ViewModel() {
///       private val _user = MutableStateFlow<UiState<User?>>(UiState.Loading)
///       val user: StateFlow<UiState<User?>> = _user
///       init { viewModelScope.launch { _user.value = UiState.Success(session.current()) } }
///       fun signIn() { ... }               // Zitadel
///       fun login(name: String) { ... }    // a test account
///       fun logout() { ... }
///     }
///
///   - `AsyncNotifier<CurrentUser?>`   ≈ that ViewModel
///   - `AsyncValue` (loading/data/error) ≈ a sealed `UiState` class, built in
///   - `build()`                        ≈ `init { }` loading the first value
///   - `state = AsyncData(user)`        ≈ `_user.value = UiState.Success(user)`
///                                        (notifies watchers; no notifyListeners())
///   - `login()` / `logout()`           ≈ ViewModel methods
class CurrentUserNotifier extends AsyncNotifier<CurrentUser?> {
  // `ref.watch` here, not `ref.read`: build() is the recipe, and watch means
  // "rebuild me if that dependency changes" (≈ combine()/flatMapLatest on an
  // upstream Flow). Methods below use `ref.read`: one-off actions, like
  // calling an injected repository from a ViewModel method.
  //
  // Two ways to be logged in: signed in with Zitadel (tokens saved; the
  // server says who we are via GET /me), or a test account picked by name
  // (just an id saved, trusted by the server only under development login).
  @override
  Future<CurrentUser?> build() async {
    final auth = ref.watch(authSessionProvider);
    if (auth != null && await auth.isSignedIn) {
      try {
        final me = _fromUser(await ref.watch(apiServiceProvider).getMe());
        unawaited(ref.read(deviceRegistrarProvider)()); // refreshes "last seen"
        return me;
      } on ApiException catch (e) {
        if (e.statusCode != 401) rethrow;
        // The sign-in was revoked or expired for good: start over.
        await auth.signOut();
        return null;
      }
    }
    return ref.watch(userSessionProvider).current();
  }

  /// Signs in through Zitadel's page (the system browser). Throws if the
  /// user backs out or the server won't accept the sign-in; the login
  /// screen shows the error and nothing changes.
  Future<void> signIn() async {
    final auth = ref.read(authSessionProvider);
    if (auth == null) throw StateError('sign-in isn\'t configured');
    await auth.signIn();
    try {
      state = AsyncData(_fromUser(await ref.read(apiServiceProvider).getMe()));
      unawaited(ref.read(deviceRegistrarProvider)());
    } on Object {
      await auth.signOut(); // Don't keep tokens for a sign-in that didn't work.
      rethrow;
    }
  }

  /// A test account, by username. Throws if the username doesn't exist; the
  /// login screen shows the error. Only a successful login touches `state`,
  /// so a failed attempt never flips the app out of the logged-out state.
  Future<void> login(String username) async {
    final user = await ref.read(apiServiceProvider).getUserByUsername(username);
    await ref.read(userSessionProvider).save(user);
    state = AsyncData(_fromUser(user));
  }

  Future<void> logout() async {
    // This user's chat history leaves the device with them (a shared
    // browser or phone shouldn't keep it). Only if it was ever opened.
    if (ref.exists(messageStoreProvider)) {
      try {
        await ref.read(messageStoreProvider).clear();
      } on Object catch (_) {
        // Still log out; the database is per user, so nobody else reads it.
      }
    }
    await ref.read(authSessionProvider)?.signOut();
    await ref.read(userSessionProvider).clear();
    state = const AsyncData(null);
  }

  static CurrentUser _fromUser(User user) =>
      CurrentUser(id: user.id, username: user.username, followerCount: user.followerCount);
}

/// How screens use it:
///   - `ref.watch(currentUserProvider)`                 ≈ `vm.user.collectAsState()`
///   - `ref.read(currentUserProvider.notifier).login()` ≈ `vm.login()`
///   - the provider itself                               ≈ `viewModel<SessionViewModel>()`'s key
final currentUserProvider = AsyncNotifierProvider<CurrentUserNotifier, CurrentUser?>(
  CurrentUserNotifier.new,
);
