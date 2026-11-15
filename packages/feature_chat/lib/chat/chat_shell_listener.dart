import 'dart:async';

import 'package:app_core/data/services/socket_provider.dart';
import 'package:app_core/session/current_user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../call/call_screen.dart';
import 'local/background_sync.dart';

/// Wraps the signed-in Home for as long as someone is signed in (see
/// ChatMiniApp.wrapSignedIn), so these keep working whichever mini-app is
/// open:
///
///   * new messages in any chat reach this device and are reported
///     delivered (background_sync.dart);
///   * an incoming call shows a banner (call_started; see
///     chatService.createCallToken), not only while Chat is open.
///
/// Compose/Android: `ConsumerStatefulWidget` + `ConsumerState` ≈ a
/// composable with ViewModels (`ref`) and lifecycle hooks
/// (`initState`/`dispose` ≈ `DisposableEffect`'s setup and `onDispose`).
class ChatShellListener extends ConsumerStatefulWidget {
  const ChatShellListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ChatShellListener> createState() => _ChatShellListenerState();
}

class _ChatShellListenerState extends ConsumerState<ChatShellListener> {
  StreamSubscription<Map<String, dynamic>>? _callSub;

  @override
  void initState() {
    super.initState();
    final userId = ref.read(currentUserProvider).requireValue!.id;
    // listenManual (not ref.read) so this widget counts as a listener and
    // keeps the autoDispose socket alive for the whole signed-in session.
    // Compose/Android: ≈ `LaunchedEffect(Unit) { socket.events.collect { ... } }`.
    ref.listenManual(socketProvider(userId), (_, socket) {
      _callSub?.cancel();
      _callSub = socket.events.listen((event) {
        if (event['type'] == 'call_started') _showIncomingCallBanner(event);
      });
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    // While signed in with the app open: new messages in any chat reach
    // this device and are reported delivered (see background_sync.dart).
    ref.watch(chatBackgroundSyncProvider);
    return widget.child;
  }

  void _showIncomingCallBanner(Map<String, dynamic> event) {
    if (!mounted) return;
    final conversationId = event['conversationId'] as int;
    final callerUsername = event['callerUsername'] as String;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Incoming call from @$callerUsername'),
        duration: const Duration(seconds: 15),
        action: SnackBarAction(
          label: 'Join',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CallScreen(conversationId: conversationId, title: '@$callerUsername'),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _callSub?.cancel();
    super.dispose();
  }
}
