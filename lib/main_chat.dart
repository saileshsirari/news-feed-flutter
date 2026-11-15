import 'package:app_core/app_core.dart';
import 'package:feature_chat/feature_chat.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Chat on its own, as a standalone app: the same sign-in, Home and push as
/// the super app, with one mini-app registered. Run it with
///
///     flutter run -t lib/main_chat.dart
///
/// Splitting chat into its own repository later means copying this file,
/// packages/app_core and packages/feature_chat (and the packages they use).
Future<void> main() => runSuperApp(title: 'Chat', slots: _slots(), onBackgroundPush: _backgroundPush);

List<MiniAppSlot> _slots() => [MiniAppSlot.eager(ChatMiniApp())];

@pragma('vm:entry-point')
Future<void> _backgroundPush(RemoteMessage push) => handlePushInBackground(push, _slots());
