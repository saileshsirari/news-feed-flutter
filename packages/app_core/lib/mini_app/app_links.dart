import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/apps_config.dart';
import 'mini_app.dart';
import 'registry.dart';

/// Addresses of screens that other mini-apps (and notifications) open.
/// Like web links between sites: chat links to a profile without importing
/// the feed's code, so either can be lifted out on its own.
///
///     app://<mini-app id>/<screen>/<id>?<details>
abstract final class AppLinks {
  static Uri profile(int userId) => Uri(scheme: 'app', host: 'feed', path: '/profile/$userId');

  static Uri conversation(int conversationId, {required String title, int? otherUserId}) => Uri(
    scheme: 'app',
    host: 'chat',
    path: '/conversation/$conversationId',
    queryParameters: {'title': title, if (otherUserId != null) 'otherUserId': '$otherUserId'},
  );

  static Uri community(int communityId) => Uri(scheme: 'app', host: 'communities', path: '/community/$communityId');

  static Uri event(int eventId) => Uri(scheme: 'app', host: 'communities', path: '/event/$eventId');

  /// The number after `/<screen>/` in [link], if [link] is that screen.
  static int? idOf(Uri link, String screen) {
    final parts = link.pathSegments;
    return parts.length == 2 && parts[0] == screen ? int.tryParse(parts[1]) : null;
  }
}

/// Opens [link] on top of the current screen. When its mini-app isn't in
/// this build, or the server has switched it off, says so instead.
Future<void> openAppLink(BuildContext context, Uri link) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final slot = slotFor(container.read(miniAppSlotsProvider), link.host);
  final config = container.read(appsConfigProvider).value ?? AppsConfig.fallback;
  if (slot == null || !config.isEnabled(slot.info.id)) {
    _notAvailable(context);
    return;
  }
  final MiniApp app;
  try {
    app = await slot.load();
  } on Object {
    if (context.mounted) _notAvailable(context, 'Couldn\'t open ${slot.info.name}. Check your connection.');
    return;
  }
  final screen = app.screenFor(link);
  if (!context.mounted) return;
  if (screen == null) return _notAvailable(context);
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}

void _notAvailable(BuildContext context, [String message = 'That isn\'t available in this app.']) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
}
