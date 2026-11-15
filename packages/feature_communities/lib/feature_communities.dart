/// Communities as a mini-app: communities, their events (RSVPs, reminders,
/// tickets) and "near me". The shell knows it only through
/// [CommunitiesMiniApp].
library;

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'communities/communities_screen.dart';
import 'communities/community_screen.dart';
import 'communities_info.dart';
import 'events/event_push.dart';
import 'events/event_screen.dart';

export 'communities_info.dart';

class CommunitiesMiniApp extends MiniApp {
  @override
  MiniAppInfo get info => communitiesInfo;

  @override
  Widget buildHome(BuildContext context) => const CommunitiesScreen();

  /// `app://communities/community/<id>` and `app://communities/event/<id>`.
  @override
  Widget? screenFor(Uri link) {
    if (AppLinks.idOf(link, 'community') case final id?) return CommunityScreen(communityId: id);
    if (AppLinks.idOf(link, 'event') case final id?) return EventScreen(eventId: id);
    return null;
  }

  /// Event notices (new, changed, cancelled, reminders), whether or not the
  /// app is open: they don't arrive any other way.
  @override
  Future<bool> showPush(Map<String, dynamic> data, {required bool appOpen}) async {
    if (data['type'] != 'event') return false;
    await showEventPush(data);
    return true;
  }
}
