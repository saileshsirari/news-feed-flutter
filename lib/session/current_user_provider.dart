import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/service_providers.dart';
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
///       fun login(name: String) { ... }
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
  @override
  Future<CurrentUser?> build() => ref.watch(userSessionProvider).current();

  /// Throws if the username doesn't exist; the login screen shows the error.
  /// Only a successful login touches `state`, so a failed attempt never
  /// flips the app out of the logged-out state.
  Future<void> login(String username) async {
    final user = await ref.read(apiServiceProvider).getUserByUsername(username);
    await ref.read(userSessionProvider).save(user);
    state = AsyncData(
      CurrentUser(id: user.id, username: user.username, followerCount: user.followerCount),
    );
  }

  Future<void> logout() async {
    await ref.read(userSessionProvider).clear();
    state = const AsyncData(null);
  }
}

/// How screens use it:
///   - `ref.watch(currentUserProvider)`                 ≈ `vm.user.collectAsState()`
///   - `ref.read(currentUserProvider.notifier).login()` ≈ `vm.login()`
///   - the provider itself                               ≈ `viewModel<SessionViewModel>()`'s key
final currentUserProvider = AsyncNotifierProvider<CurrentUserNotifier, CurrentUser?>(
  CurrentUserNotifier.new,
);
