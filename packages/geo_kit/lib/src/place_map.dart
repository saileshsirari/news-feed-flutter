import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

import 'geo_point.dart';

/// Where map pictures come from. OpenStreetMap's tiles are free for light
/// use if every map credits OpenStreetMap and names the app
/// (userAgentPackageName); a busy app would move to a paid tile host or
/// its own, by changing only this.
class MapTiles {
  const MapTiles._(this.urlTemplate, this.userAgentPackageName);

  const MapTiles.openStreetMap({required String userAgentPackageName})
      : this._('https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName);

  /// No pictures, just pins on a blank map (widget tests: no network).
  static const none = MapTiles._(null, '');

  final String? urlTemplate;
  final String userAgentPackageName;
}

/// A pin on a [PlaceMap].
class MapPin {
  const MapPin({required this.point, required this.label, this.onTap, this.highlighted = false});

  final GeoPoint point;
  final String label;
  final VoidCallback? onTap;
  final bool highlighted;
}

/// A map with pins, and optionally a circle (how far "near me" looks).
class PlaceMap extends StatelessWidget {
  const PlaceMap({
    super.key,
    required this.tiles,
    required this.center,
    this.zoom = 13,
    this.pins = const [],
    this.radiusKm,
    this.controller,
    this.onMoved,
    this.interactive = true,
  });

  final MapTiles tiles;
  final GeoPoint center;
  final double zoom;
  final List<MapPin> pins;

  /// A circle this big around [center].
  final double? radiusKm;
  final MapController? controller;

  /// The map's centre after the person moved it.
  final ValueChanged<GeoPoint>? onMoved;

  /// False: a still picture of a place (an event's page), no panning.
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center.latLng,
        initialZoom: zoom,
        interactionOptions: InteractionOptions(flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none),
        onPositionChanged: onMoved == null
            ? null
            : (camera, hasGesture) {
                if (hasGesture) onMoved!(GeoPoint.fromLatLng(camera.center));
              },
      ),
      children: [
        if (tiles.urlTemplate != null)
          TileLayer(urlTemplate: tiles.urlTemplate, userAgentPackageName: tiles.userAgentPackageName),
        if (radiusKm != null)
          CircleLayer(circles: [
            CircleMarker(
              point: center.latLng,
              radius: radiusKm! * 1000,
              useRadiusInMeter: true,
              color: colors.primary.withValues(alpha: 0.08),
              borderColor: colors.primary.withValues(alpha: 0.5),
              borderStrokeWidth: 1.5,
            ),
          ]),
        MarkerLayer(
          markers: [
            for (final pin in pins)
              Marker(
                point: pin.point.latLng,
                width: 40,
                height: 40,
                alignment: Alignment.topCenter, // the pin's tip on the spot
                child: Semantics(
                  label: pin.label,
                  button: pin.onTap != null,
                  child: GestureDetector(
                    onTap: pin.onTap,
                    child: Tooltip(
                      message: pin.label,
                      child: Icon(Icons.location_on, size: 40, color: pin.highlighted ? colors.tertiary : colors.primary),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (tiles.urlTemplate != null)
          RichAttributionWidget(
            attributions: [
              TextSourceAttribution(
                'OpenStreetMap contributors',
                onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
              ),
            ],
          ),
      ],
    );
  }
}
