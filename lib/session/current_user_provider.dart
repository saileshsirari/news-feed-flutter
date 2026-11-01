import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/service_providers.dart';
import 'user_session.dart';

/// Who's logged in: loading while the saved session is read at startup,
/// then null (logged out) or the user. This used to live inside
/// FeedViewModel, so chat and calls had to reach into the feed's view model
/// to learn the user id; now everything watches this instead.
class CurrentUserNotifier extends AsyncNotifier<CurrentUser?> {
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

final currentUserProvider = AsyncNotifierProvider<CurrentUserNotifier, CurrentUser?>(
  CurrentUserNotifier.new,
);
