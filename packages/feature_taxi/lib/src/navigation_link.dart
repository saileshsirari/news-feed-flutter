import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geo_kit/geo_kit.dart';

/// Turn-by-turn directions for the driver live in geo_kit (shared with
/// chat's "Directions" to a shared location): see geo_kit's directions.dart.
export 'package:geo_kit/geo_kit.dart' show LinkLauncher, navigationLinks, openDirections;

/// Opens a link outside the app (the phone's maps app). Tests swap it.
final linkLauncherProvider = Provider<LinkLauncher>((_) => launchExternally);
