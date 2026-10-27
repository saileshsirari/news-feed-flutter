import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../call/call_screen.dart';
import '../chat/conversations_list_screen.dart';
import '../feed/feed_screen.dart';
import '../feed/feed_view_model.dart';

/// Two tabs: the existing feed, and the new chat/contacts list. Both share
/// the one logged-in FeedViewModel instance above this widget in the tree —
/// see main.dart — so there's exactly one WebSocket connection and one
/// current-user id for the whole app, not one per tab. Also the one place
/// that listens for call_started (see chatService.createCallToken) — this
/// widget stays mounted for the whole logged-in session regardless of which
/// tab is showing, so an incoming call banner can appear no matter where
/// you're looking, not just while the Chat tab happens to be open.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;
  StreamSubscription<Map<String, dynamic>>? _callSub;
  int? _subscribedForUserId;

  @override
  Widget build(BuildContext context) {
    final feedVm = context.watch<FeedViewModel>();
    final a = context.read<FeedViewModel>();
    final currentUserId = feedVm.currentUserId;
    if (currentUserId == null) {
      // Briefly true right after login while FeedViewModel's own state
      // settles — nothing meaningful to show yet.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // FeedViewModel reconnects its socket on every login (see
    // _connectRealtime), so re-subscribe whenever the user (and therefore
    // the socket instance) changes, rather than once in initState — this
    // widget is created before the socket exists on a cold start.
    if (_subscribedForUserId != currentUserId) {
      _subscribedForUserId = currentUserId;
      _callSub?.cancel();
      _callSub = feedVm.socket?.events.listen((event) {
        if (event['type'] == 'call_started') _showIncomingCallBanner(event);
      });
    }

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
