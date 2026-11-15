/// The super app's shared core: sign-in and session, the API client and
/// models, push, theme, and the [MiniApp] interface every mini-app plugs
/// in through. Mini-apps depend on this package and never on each other's
/// screens (they open them by link: [AppLinks]).
library;

export 'config/apps_config.dart';
export 'mini_app/app_links.dart';
export 'mini_app/mini_app.dart';
export 'mini_app/registry.dart';
export 'push/local_notifications.dart' show NotificationChannel, showLocalNotification;
export 'push/push_setup.dart' show handlePushInBackground, savedSignIn;
export 'shell/home_shell.dart' show HomeShell, MiniAppTile, openMiniApp;
export 'shell/super_app.dart';
export 'shell/theme.dart';
