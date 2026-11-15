/// The news feed as a mini-app: posts, comments, likes and profiles. The
/// shell knows it only through [FeedMiniApp].
library;

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'feed/feed_screen.dart';
import 'feed_info.dart';
import 'profile/profile_screen.dart';

export 'feed_info.dart';

class FeedMiniApp extends MiniApp {
  @override
  MiniAppInfo get info => feedInfo;

  @override
  Widget buildHome(BuildContext context) => const FeedScreen();

  /// `app://feed/profile/<userId>`: anyone's profile, from chat or a community.
  @override
  Widget? screenFor(Uri link) => switch (AppLinks.idOf(link, 'profile')) {
    final userId? => ProfileScreen(userId: userId),
    null => null,
  };
}
