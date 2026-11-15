import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geo_kit/geo_kit.dart';

import '../data/services/service_providers.dart';
import '../session/current_user_provider.dart';

/// What the server says at startup (GET /config/apps): which mini-apps are
/// open, and which map services to use. Like the "open" signs in a mall:
/// every shop is built into the app, the server says which to show.
@immutable
class AppsConfig {
  const AppsConfig({required this.apps, required this.maps, this.fromServer = true});

  /// Mini-app id -> its optional parts ("events": true, ...).
  final Map<String, Map<String, bool>> apps;
  final MapSettings maps;

  /// False when the server couldn't be asked (offline, or an older server
  /// without /config/apps): then every compiled-in mini-app is shown.
  final bool fromServer;

  /// When the server couldn't be asked: show everything, with OpenStreetMap.
  static const fallback = AppsConfig(apps: {}, maps: MapSettings.openStreetMap, fromServer: false);

  bool isEnabled(String miniAppId) => !fromServer || apps.containsKey(miniAppId);

  /// An optional part of a mini-app, e.g. feature('communities', 'tickets').
  /// On when the server didn't say otherwise.
  bool feature(String miniAppId, String name) => apps[miniAppId]?[name] ?? !fromServer;

  factory AppsConfig.fromJson(Map<String, dynamic> json) => AppsConfig(
    apps: {
      for (final app in (json['apps'] as List? ?? const []).cast<Map<String, dynamic>>())
        app['id'] as String: {
          for (final MapEntry(:key, :value) in (app['features'] as Map<String, dynamic>? ?? const {}).entries)
            key: value == true,
        },
    },
    maps: json['maps'] is Map<String, dynamic>
        ? MapSettings.fromJson(json['maps'] as Map<String, dynamic>)
        : MapSettings.openStreetMap,
  );
}

/// Map pictures and place search, as set on the server (so production can
/// move off OpenStreetMap's free servers without an app update).
@immutable
class MapSettings {
  const MapSettings({
    required this.tileUrl,
    required this.attribution,
    required this.attributionUrl,
    this.placeSearch = true,
    this.routing = 'none',
  });

  static const openStreetMap = MapSettings(
    tileUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap contributors',
    attributionUrl: 'https://www.openstreetmap.org/copyright',
  );

  final String tileUrl;
  final String attribution;
  final String attributionUrl;

  /// Place search through our server (/geo/search) is on.
  final bool placeSearch;

  /// The server's routing provider for directions (taxi, later); "none" now.
  final String routing;

  factory MapSettings.fromJson(Map<String, dynamic> json) => MapSettings(
    tileUrl: json['tileUrl'] as String? ?? openStreetMap.tileUrl,
    attribution: json['attribution'] as String? ?? openStreetMap.attribution,
    attributionUrl: json['attributionUrl'] as String? ?? openStreetMap.attributionUrl,
    placeSearch: json['placeSearch'] as bool? ?? true,
    routing: json['routing'] as String? ?? 'none',
  );

  /// For geo_kit's maps.
  MapTiles toTiles({required String userAgentPackageName}) => MapTiles.custom(
    urlTemplate: tileUrl,
    userAgentPackageName: userAgentPackageName,
    attribution: attribution,
    attributionUrl: attributionUrl,
  );
}

/// Asked once per signed-in user. A failure (offline, older server) falls
/// back to "everything on" rather than an empty Home.
final appsConfigProvider = FutureProvider<AppsConfig>((ref) async {
  final userId = ref.watch(currentUserProvider.select((s) => s.value?.id));
  final api = ref.watch(apiServiceProvider);
  try {
    return AppsConfig.fromJson(await api.getAppsConfig(userId: userId));
  } on Object catch (e) {
    debugPrint('[apps] couldn\'t ask the server which mini-apps are on, showing all: $e');
    return AppsConfig.fallback;
  }
});
