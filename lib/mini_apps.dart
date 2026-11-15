import 'package:app_core/app_core.dart';
// Each mini-app's tile (tiny, always loaded)...
import 'package:feature_communities/communities_info.dart';
import 'package:feature_feed/feed_info.dart';
import 'package:feature_taxi/taxi_info.dart';
// ...and its code. Chat is global (messages and calls reach you anywhere),
// so it loads at start. Feed and communities are deferred: on the web their
// code downloads the first time you open them, so the first page is
// smaller; on Android/iOS deferred imports are compiled in as usual (iOS
// can't download code, and Play Store deferred components aren't set up).
import 'package:feature_chat/feature_chat.dart';
import 'package:feature_communities/feature_communities.dart' deferred as communities;
import 'package:feature_feed/feature_feed.dart' deferred as feed;
import 'package:feature_taxi/feature_taxi.dart' deferred as taxi;

/// Every mini-app in the full super app, in Home-grid order. The server
/// then chooses which of these to show (GET /config/apps).
///
/// Adding one: a `packages/feature_<name>` with an info and a MiniApp, a
/// line here, and its id in the server's MINI_APPS.
List<MiniAppSlot> allMiniApps() => [
  MiniAppSlot.deferred(feedInfo, () async {
    await feed.loadLibrary();
    return feed.FeedMiniApp();
  }),
  MiniAppSlot.eager(ChatMiniApp()),
  MiniAppSlot.deferred(communitiesInfo, () async {
    await communities.loadLibrary();
    return communities.CommunitiesMiniApp();
  }),
  MiniAppSlot.deferred(taxiInfo, () async {
    await taxi.loadLibrary();
    return taxi.TaxiMiniApp();
  }),
];
