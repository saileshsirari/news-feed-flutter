import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:oidc_auth/oidc_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../mini_app/mini_app.dart';

/// Starts Firebase on Android and iOS, so FcmChannel can work, and hands
/// each push to the mini-app it's for. Without Firebase settings for this
/// platform (e.g. iOS before the Apple account), push is simply off;
/// nothing else is affected.
///
/// [onBackground] must be a top-level function (Firebase runs it in its
/// own isolate, the app's memory not shared): each main.dart has one that
/// calls [handlePushInBackground] with its own mini-apps.
Future<void> setUpPush({
  required List<MiniAppSlot> slots,
  required Future<void> Function(RemoteMessage push) onBackground,
}) async {
  if (kIsWeb || !(defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
    return;
  }
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(onBackground);
    // With the app open, chat arrives over the socket (its mini-app skips
    // those); event notices still need showing.
    FirebaseMessaging.onMessage.listen((push) => routePush(slots, push.data, appOpen: true));
  } on Object catch (e) {
    debugPrint('[push] Firebase not set up for this platform: $e');
  }
}

/// A push while the app is in the background or closed. It carries only ids
/// (Google never sees the text); the mini-app it's for fetches the rest from
/// our server with the saved sign-in, and shows it.
Future<void> handlePushInBackground(RemoteMessage push, List<MiniAppSlot> slots) async {
  await Firebase.initializeApp();
  await routePush(slots, push.data, appOpen: false);
}

/// Who's signed in on this device, for pushes: saved where a push in the
/// background (its own isolate, no providers) can read it.
const _pushRecipientKey = 'push_recipient_user_id';

/// Remembers that [userId] is the account signed in here (null: none).
Future<void> setPushRecipient(int? userId) async {
  final prefs = await SharedPreferences.getInstance();
  if (userId == null) {
    await prefs.remove(_pushRecipientKey);
  } else {
    await prefs.setInt(_pushRecipientKey, userId);
  }
}

/// Whether [data] (a push) is for whoever is signed in here. A push says
/// whom it's for ("to"); one for another account (this phone signed in as
/// someone else before, and the server still had it) is dropped rather
/// than shown to the wrong person. Older servers didn't say: shown.
Future<bool> isForThisDevice(Map<String, dynamic> data) async {
  final to = int.tryParse('${data['to'] ?? ''}');
  if (to == null) return true;
  return (await SharedPreferences.getInstance()).getInt(_pushRecipientKey) == to;
}

/// Offers [data] to each mini-app in turn until one shows it, like a
/// mailroom handing a letter to the right department. A push for an
/// account that isn't signed in here is dropped (see [isForThisDevice]).
Future<bool> routePush(List<MiniAppSlot> slots, Map<String, dynamic> data, {required bool appOpen}) async {
  if (!await isForThisDevice(data)) {
    debugPrint('[push] dropped: it\'s for another account than the one signed in here');
    return true;
  }
  for (final slot in slots) {
    try {
      if (await (await slot.load()).showPush(data, appOpen: appOpen)) return true;
    } on Object catch (e) {
      debugPrint('[push] ${slot.info.id} couldn\'t show a push: $e');
    }
  }
  return false;
}

/// The saved sign-in's server and HTTP client, for code running outside
/// the app's providers (a push in the background). Null when signed out
/// or sign-in isn't set up.
Future<({AppConfig config, http.Client client})?> savedSignIn() async {
  final config = AppConfig.fromEnvironment();
  final oidc = config.oidc;
  if (oidc == null) return null;
  final auth = AuthSession(client: OidcClient(oidc), store: SecureTokenStore());
  if (!await auth.isSignedIn) return null;
  return (config: config, client: AuthorizedClient(auth.accessToken));
}
