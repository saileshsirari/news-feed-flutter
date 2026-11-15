import 'package:app_core/app_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'mini_apps.dart';

/// The full super app: every mini-app, on a Home grid.
///
/// A standalone app is the same three lines with a shorter list: see
/// main_chat.dart (`flutter run -t lib/main_chat.dart`).
Future<void> main() => runSuperApp(title: 'News Feed', slots: allMiniApps(), onBackgroundPush: _backgroundPush);

/// A push while the app is in the background or closed (Firebase runs this
/// in its own isolate, so it builds its own list of mini-apps).
@pragma('vm:entry-point')
Future<void> _backgroundPush(RemoteMessage push) => handlePushInBackground(push, allMiniApps());
