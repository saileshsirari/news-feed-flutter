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
final socketProvider = Provider.autoDispose.family<AppSocket, int>((ref, userId) {
  final socket = AppSocket(userId, ref.watch(appConfigProvider))..connect();
  ref.onDispose(socket.disconnect);
  return socket;
});
