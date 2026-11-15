import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geo_kit/geo_kit.dart';
import 'package:url_launcher/url_launcher.dart';

/// Turn-by-turn directions for the driver, by handing over to the phone's
/// own maps app, as many Ola and Uber drivers do. Free: it's only a link,
/// with no routing service or key of ours involved. Building voice
/// navigation into the app would need a paid SDK.
///
/// Which links, best first:
///
/// ```text
/// Android   google.navigation:q=<lat>,<lng>&mode=d    Google Maps, straight into driving navigation
///           then the web link below (any maps app or the browser)
/// iPhone    maps.apple.com/?daddr=...&dirflg=d         Apple Maps (always there), driving
/// web       google.com/maps/dir/?api=1&destination=... Google Maps in a new tab
/// ```
///
/// Only the place being driven to is in the link, never who's riding.
/// The driver is sent the exact pickup only after accepting, and chooses
/// to open the maps app.
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

/// Opens [link] outside the app; false if nothing could. Tests swap it.
typedef LinkLauncher = Future<bool> Function(Uri link);

final linkLauncherProvider = Provider<LinkLauncher>(
  (_) => (link) async {
    try {
      return await launchUrl(link, mode: LaunchMode.externalApplication);
    } on Object {
      return false; // no app for that kind of link: try the next one
    }
  },
);

/// Starts directions to [to] in the first maps app that opens. False if
/// none did (the screen then says so).
Future<bool> openDirections(LinkLauncher launch, GeoPoint to, {required TargetPlatform platform}) async {
  for (final link in navigationLinks(to, platform: platform)) {
    if (await launch(link)) return true;
  }
  return false;
}
