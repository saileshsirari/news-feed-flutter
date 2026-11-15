import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderListenable;

/// What the Home grid needs to draw a tile, before any of the mini-app's
/// code is loaded: like the label on a shop's door, readable while the shop
/// is still shut. Kept apart from [MiniApp] so the web build can show the
/// tile right away and download the shop itself (a deferred import) only
/// when someone taps it.
@immutable
class MiniAppInfo {
  const MiniAppInfo({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    this.isGlobal = false,
  });

  /// The server's name for it too (GET /config/apps), and the host of its
  /// links: `app://<id>/...`.
  final String id;
  final String name;
  final IconData icon;
  final Color color;

  /// Lives in the global bar as well as the grid, and is loaded at start
  /// (chat: messages and calls arrive whichever mini-app you're in).
  final bool isGlobal;
}

/// One mini-app: a self-contained part of the super app (feed, chat,
/// communities; taxi next). It plugs into the shell through this interface
/// only, so it can be lifted into its own app later: a tiny main.dart that
/// registers just it (see lib/main_chat.dart).
///
/// Android comparison: each one is like a feature module with its own
/// launcher activity; [screenFor] is its deep-link intent filter.
abstract class MiniApp {
  MiniAppInfo get info;

  /// Its first screen, opened full screen from the Home grid. Its own
  /// screens push on top as usual; the back arrow at the bottom of the
  /// stack returns Home.
  Widget buildHome(BuildContext context);

  /// The screen at [link] (`app://<info.id>/<path>`), or null if it has no
  /// such screen. How other mini-apps open its screens without importing
  /// them, e.g. chat opening a profile (`app://feed/profile/42`).
  Widget? screenFor(Uri link) => null;

  /// Shows a push meant for it ([data] is the push's id-only payload) and
  /// says whether it was. [appOpen]: the app is in front (chat then skips
  /// it, since the socket already delivered the message).
  Future<bool> showPush(Map<String, dynamic> data, {required bool appOpen}) async => false;

  /// The number on its tile (unread chats, say), or null for none.
  ProviderListenable<int>? get badgeCount => null;

  /// Wraps the signed-in Home for as long as someone is signed in: for
  /// listeners that must outlive any one screen (chat's incoming-call
  /// banner and background sync).
  Widget wrapSignedIn(Widget child) => child;

  /// Once at app start, before the first screen (global, eagerly loaded
  /// mini-apps only): chat loads its encryption library here.
  Future<void> initialise() async {}

  /// Provider overrides it needs app-wide (applied at start; only global,
  /// eagerly loaded mini-apps can use these).
  List<Override> get overrides => const [];

  /// This device was registered with the server (after a sign-in).
  Future<void> onDeviceRegistered(Ref ref, int userId, int deviceId) async {}

  /// [userId] is signing out: clear what's theirs on this device.
  Future<void> onSignOut(Ref ref, int userId) async {}
}

/// A mini-app as compiled into this build: its [info] always, its code
/// either right away or on first use ([load]). See lib/mini_apps.dart.
class MiniAppSlot {
  /// Already in memory (Android/iOS, and global mini-apps everywhere).
  MiniAppSlot.eager(MiniApp app) : info = app.info, _loader = null, _loaded = app;

  /// Downloaded on first use on the web (a Dart deferred import); on
  /// Android/iOS [load] completes at once, since the code is compiled in.
  MiniAppSlot.deferred(this.info, Future<MiniApp> Function() load) : _loader = load;

  final MiniAppInfo info;
  final Future<MiniApp> Function()? _loader;
  MiniApp? _loaded;
  Future<MiniApp>? _loading;

  /// The mini-app, if its code is in memory already.
  MiniApp? get loaded => _loaded;

  Future<MiniApp> load() {
    if (_loaded != null) return Future.value(_loaded);
    return _loading ??= _loader!().then(
      (app) {
        assert(app.info.id == info.id, 'slot ${info.id} loaded mini-app ${app.info.id}');
        return _loaded = app;
      },
      onError: (Object e, StackTrace s) {
        _loading = null; // a failed download can be retried
        Error.throwWithStackTrace(e, s);
      },
    );
  }
}
