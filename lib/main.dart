import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'feed/feed_view_model.dart';
import 'feed/login_screen.dart';
import 'home/home_screen.dart';
import 'network/api_client.dart';
import 'session/user_session.dart';

void main() {
  runApp(const NewsFeedApp());
}

class NewsFeedApp extends StatelessWidget {
  const NewsFeedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => ApiClient()),
        Provider(create: (_) => UserSession()),
        // Created once for the whole app's lifetime, not per screen — this is
        // what makes FeedViewModel.socket a single shared WebSocket that both
        // the feed tab and every chat screen listen to (see home_screen.dart).
        ChangeNotifierProvider(
          create: (context) => FeedViewModel(context.read<ApiClient>(), context.read<UserSession>()),
        ),
      ],
      child: MaterialApp(
        title: 'News Feed',
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
        home: const _RootScreen(),
      ),
    );
  }
}

class _RootScreen extends StatelessWidget {
  const _RootScreen();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<FeedViewModel>();
    if (!vm.loggedIn) {
      return LoginScreen(loggingIn: vm.loggingIn, error: vm.loginError, onLogin: vm.login);
    }
    return const HomeScreen();
  }
}
