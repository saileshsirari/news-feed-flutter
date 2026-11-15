import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../data/services/media_providers.dart';
import '../data/services/service_providers.dart';
import '../mini_app/mini_app.dart';
import '../mini_app/registry.dart';
import '../push/push_setup.dart';
import '../session/current_user_provider.dart';
import '../session/login_screen.dart';
import 'home_shell.dart';
import 'theme.dart';

/// Starts an app made of [slots]: the full super app (lib/main.dart) or a
/// standalone one with a single mini-app (lib/main_chat.dart). The same
/// sign-in, push and Home for both; only the list differs.
///
/// [onBackgroundPush] must be a top-level function in the main.dart (see
/// setUpPush) that calls handlePushInBackground with the same slots.
Future<void> runSuperApp({
  required String title,
  required List<MiniAppSlot> slots,
  required Future<void> Function(RemoteMessage push) onBackgroundPush,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase for push on Android/iOS (no-op elsewhere, and if not set up).
  await setUpPush(slots: slots, onBackground: onBackgroundPush);
  // Global mini-apps start now (chat's encryption library); a failure must
  // never stop the app.
  for (final slot in slots) {
    try {
      await slot.loaded?.initialise();
    } on Object catch (e) {
      debugPrint('[apps] ${slot.info.id} didn\'t start: $e');
    }
  }
  // ProviderScope holds every provider's value for the whole app (the
  // services, the current user, the socket). Providers themselves are just
  // global recipes; the state lives here.
  // Compose/Android: ≈ `@HiltAndroidApp` + the ViewModelStore.
  runApp(
    ProviderScope(
      overrides: superAppOverrides(slots),
      child: SuperApp(title: title),
    ),
  );
}

/// What every super app's ProviderScope needs: its mini-apps, the media
/// package's server, and each loaded mini-app's own overrides.
List<Override> superAppOverrides(List<MiniAppSlot> slots) => [
  miniAppSlotsProvider.overrideWithValue(slots),
  ...mediaOverrides,
  for (final slot in slots) ...?slot.loaded?.overrides,
];

class SuperApp extends StatelessWidget {
  const SuperApp({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: title,
    theme: appTheme(),
    home: _Root(title: title),
  );
}

/// Signed out: the login screen. Signed in: Home, wrapped by each loaded
/// mini-app's long-lived listeners (chat's call banner and sync).
///
/// Compose/Android: ≈ `when (val s = vm.user.collectAsState().value) { ... }`.
class _Root extends ConsumerWidget {
  const _Root({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentUserProvider);
    // Signed out from inside a mini-app (the feed's menu, say): its screens
    // sit on top of this one, so close them all, back to the login screen.
    ref.listen(currentUserProvider.select((s) => s.value?.id), (before, now) {
      if (before != null && now == null) Navigator.of(context).popUntil((route) => route.isFirst);
    });
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
    Widget home = HomeShell(title: title);
    for (final slot in ref.watch(miniAppSlotsProvider)) {
      home = slot.loaded?.wrapSignedIn(home) ?? home;
    }
    return home;
  }
}
