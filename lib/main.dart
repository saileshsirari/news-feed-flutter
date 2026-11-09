import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/services/media_providers.dart';
import 'push/push_setup.dart';
import 'package:mls_crypto/mls_crypto.dart';
import 'data/services/service_providers.dart';
import 'feed/login_screen.dart';
import 'home/home_screen.dart';
import 'session/current_user_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase for push on Android/iOS (no-op elsewhere, and if not set up).
  await setUpPush();
  // The end-to-end encryption library (Rust). Not used by any chat yet; a
  // failure to load must never stop the app.
  try {
    await initMlsCrypto();
    // Debug builds only: prove the library works on this device by having
    // two pretend devices exchange an encrypted message. Shows in the log.
    if (kDebugMode) debugPrint('[e2e] self-test: ${await mlsSelfTest()}');
  } on Object catch (e) {
    debugPrint('[e2e] encryption library not available: $e');
  }
  // ProviderScope holds every provider's value for the whole app (the
  // services, the current user, the socket). Providers themselves are just
  // global recipes; the state lives here.
  // Compose/Android: ≈ `@HiltAndroidApp` + the ViewModelStore, the container
  // that holds every singleton and ViewModel instance.
  runApp(ProviderScope(overrides: mediaOverrides, child: const NewsFeedApp()));
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

/// Compose/Android equivalent:
///
///     @Composable fun Root(vm: SessionViewModel = hiltViewModel()) {
///       when (val s = vm.user.collectAsState().value) { Loading -> ...; ... }
///     }
///
///   - `ConsumerWidget`        ≈ a `@Composable` function that can read ViewModels
///   - `WidgetRef ref`         ≈ access to `hiltViewModel()` / `LocalX.current`
///   - `ref.watch(provider)`   ≈ `collectAsState()`: read + recompose on change
///   - `ref.read(provider...)` ≈ grabbing the ViewModel to call a method, no recompose
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
      final notifier = ref.read(currentUserProvider.notifier);
      return LoginScreen(
        onLogin: notifier.login,
        // Only when sign-in is configured (always, outside tests).
        onSignIn: ref.watch(authSessionProvider) == null ? null : notifier.signIn,
      );
    }
    return const HomeScreen();
  }
}
