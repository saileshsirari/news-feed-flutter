import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../call/call_screen.dart';
import '../chat/conversations_list_screen.dart';
import '../data/services/socket_provider.dart';
import '../feed/feed_screen.dart';
import '../session/current_user_provider.dart';

/// Two tabs: the existing feed, and the new chat/contacts list. Only exists
/// while someone is logged in (see main.dart's _RootScreen), and both tabs
/// share that user's one socketProvider connection. Also the one place
/// that listens for call_started (see chatService.createCallToken) — this
/// widget stays mounted for the whole logged-in session regardless of which
/// tab is showing, so an incoming call banner can appear no matter where
/// you're looking, not just while the Chat tab happens to be open.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tabIndex = 0;
  StreamSubscription<Map<String, dynamic>>? _callSub;

  @override
  void initState() {
    super.initState();
    final userId = ref.read(currentUserProvider).requireValue!.id;
    // listenManual (not ref.read) so this widget counts as a listener and
    // keeps the autoDispose socket alive for the whole logged-in session.
    // fireImmediately hands us the socket right away; the old
    // "re-subscribe when the user id changes" bookkeeping is gone because
    // this widget never outlives its user.
    ref.listenManual(socketProvider(userId), (_, socket) {
      _callSub?.cancel();
      _callSub = socket.events.listen((event) {
        if (event['type'] == 'call_started') _showIncomingCallBanner(event);
      });
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const FeedScreen(),
      const ConversationsListScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _tabIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Feed'),
          NavigationDestination(icon: Icon(Icons.chat_outlined), selectedIcon: Icon(Icons.chat), label: 'Chat'),
        ],
      ),
    );
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
