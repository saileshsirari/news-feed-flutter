import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'feed/login_screen.dart';
import 'home/home_screen.dart';
import 'session/current_user_provider.dart';

void main() {
  // ProviderScope holds every provider's value for the whole app (the
  // services, the current user, the socket). Providers themselves are just
  // global recipes; the state lives here.
  runApp(const ProviderScope(child: NewsFeedApp()));
}

class NewsFeedApp extends StatelessWidget {
  const NewsFeedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'News Feed',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const _RootScreen(),
    );
  }
}

class _RootScreen extends ConsumerWidget {
  const _RootScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentUserProvider);
    // Only at startup, while the saved session is read from disk.
    if (session.isLoading && !session.hasValue) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (session.value == null) {
      return LoginScreen(onLogin: ref.read(currentUserProvider.notifier).login);
    }
    return const HomeScreen();
  }
}
