import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'geo_point.dart';

/// Directions to a place in the phone's own maps app (Google Maps, Apple
/// Maps): free, as it's only a link, with no routing service or key of
/// ours involved. Taxi drivers use it to reach a pickup; chat uses it to
/// get to a shared location.
///
/// Which links, best first:
///
/// ```text
/// Android   google.navigation:q=<lat>,<lng>&mode=d    Google Maps, straight into navigation
///           then the web link below (any maps app or the browser)
/// iPhone    maps.apple.com/?daddr=...&dirflg=d         Apple Maps (always there)
/// web       google.com/maps/dir/?api=1&destination=... Google Maps in a new tab
/// ```
///
/// Only the destination is in the link: nothing about who's there.
List<Uri> navigationLinks(GeoPoint to, {required TargetPlatform platform, bool isWeb = kIsWeb}) {
  final where = '${to.lat},${to.lng}';
  final web = Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': where,
    'travelmode': 'driving',
    'dir_action': 'navigate',
  });
  if (isWeb) return [web];
  return switch (platform) {
    TargetPlatform.android => [Uri.parse('google.navigation:q=$where&mode=d'), web],
    TargetPlatform.iOS => [
      Uri.https('maps.apple.com', '/', {'daddr': where, 'dirflg': 'd'}),
      web,
    ],
    _ => [web],
  };
}

/// Opens a link outside the app; false if nothing could. Tests swap it.
typedef LinkLauncher = Future<bool> Function(Uri link);

/// The real one: hands the link to the phone (its maps app, or a browser).
Future<bool> launchExternally(Uri link) async {
  try {
    return await launchUrl(link, mode: LaunchMode.externalApplication);
  } on Object {
    return false; // no app for that kind of link: try the next one
  }
}

/// Starts directions to [to] in the first maps app that opens. False if
/// none did (the screen then says so).
Future<bool> openDirections(LinkLauncher launch, GeoPoint to, {required TargetPlatform platform}) async {
  for (final link in navigationLinks(to, platform: platform)) {
    if (await launch(link)) return true;
  }
  return false;
}
