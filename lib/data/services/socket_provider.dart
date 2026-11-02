import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_socket.dart';
import 'service_providers.dart';

/// The one realtime connection for a logged-in user, shared by the feed, the
/// chat screens and HomeScreen's incoming-call banner.
///
/// Before, FeedViewModel opened the socket after login and every screen
/// copied `feedVm.socket` once when it was built — so a screen built a
/// moment too early kept a null socket forever (see the old ordering comment
/// in FeedViewModel's git history). Now there's nothing to copy too early:
/// `ref.watch(socketProvider(userId))` connects on first use and always
/// returns the live socket.
///
/// autoDispose: once nothing watches it (the user logged out, so HomeScreen
/// and every chat screen are gone), it disconnects.
///
/// Compose/Android equivalent: a Hilt-provided object scoped to "while
/// logged in", like a custom `@UserScope` component.
///   - `.family<AppSocket, int>` + `socketProvider(userId)`
///       ≈ `@AssistedInject` / a factory: one instance per user id
///   - `.autoDispose`
///       ≈ a scope that ends when its last user is gone, like a ViewModel
///         cleared when its screen leaves the back stack
///   - `ref.onDispose(socket.disconnect)` ≈ `ViewModel.onCleared()`
final socketProvider = Provider.autoDispose.family<AppSocket, int>((ref, userId) {
  final socket = AppSocket(userId, ref.watch(appConfigProvider))..connect();
  ref.onDispose(socket.disconnect);
  return socket;
});
