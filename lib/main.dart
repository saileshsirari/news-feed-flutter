import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/app_config.dart';
import 'data/services/api_service.dart';
import 'feed/feed_view_model.dart';
import 'feed/login_screen.dart';
import 'home/home_screen.dart';
import 'session/user_session.dart';

void main() {
  runApp(NewsFeedApp(config: AppConfig.fromEnvironment()));
}

class NewsFeedApp extends StatelessWidget {
  const NewsFeedApp({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: config),
        Provider(create: (context) => ApiService(context.read<AppConfig>())),
        Provider(create: (_) => UserSession()),
        // Created once for the whole app's lifetime, not per screen — this is
        // what makes FeedViewModel.socket a single shared WebSocket that both
        // the feed tab and every chat screen listen to (see home_screen.dart).
        ChangeNotifierProvider(
          create: (context) => FeedViewModel(
            context.read<ApiService>(),
            context.read<UserSession>(),
            context.read<AppConfig>(),
          ),
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
