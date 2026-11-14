import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'geo_point.dart';
import 'my_location.dart';
import 'place.dart';
import 'place_map.dart';

/// Opens a full-screen map to choose a place: search for one, or move the
/// map under the pin. Returns null if the person backs out.
///
/// [areaOnly]: for "where's this community based": the answer is rounded to
/// about a kilometre and named after the area, not the street.
Future<Place?> pickPlace(
  BuildContext context, {
  required PlaceSearch search,
  required MapTiles tiles,
  LocationSource? location,
  Place? initial,
  GeoPoint? near,
  bool areaOnly = false,
  String? title,
}) =>
    Navigator.of(context).push<Place>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PlacePickerScreen(
          search: search,
          tiles: tiles,
          location: location,
          initial: initial,
          near: near,
          areaOnly: areaOnly,
          title: title ?? (areaOnly ? 'Choose an area' : 'Choose a place'),
        ),
      ),
    );

class PlacePickerScreen extends StatefulWidget {
  const PlacePickerScreen({
    super.key,
    required this.search,
    required this.tiles,
    required this.title,
    this.location,
    this.initial,
    this.near,
    this.areaOnly = false,
  });

  final PlaceSearch search;
  final MapTiles tiles;
  final LocationSource? location;
  final Place? initial;
  final GeoPoint? near;
  final bool areaOnly;
  final String title;

  /// Where the map opens with nothing else to go on: Bengaluru.
  static const fallbackCenter = GeoPoint(12.9716, 77.5946);

  @override
  State<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends State<PlacePickerScreen> {
  final _map = MapController();
  final _query = TextEditingController();

  late GeoPoint _center = widget.initial?.point ?? widget.near ?? PlacePickerScreen.fallbackCenter;

  /// The place under the pin when it came from a search (so its name is
  /// known); null once the map is moved by hand.
  late Place? _named = widget.initial;

  List<Place>? _results;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    _map.dispose();
    super.dispose();
  }

  /// Only when asked (the Search key or button), never per keystroke: the
  /// free OpenStreetMap service allows about one request a second for
  /// everyone using this app together.
  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.length < 2) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await widget.search.search(q, near: _center);
      setState(() => _results = results);
    } on Exception {
      setState(() => _error = 'Place search isn\'t working right now. Move the map to the spot instead.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goTo(GeoPoint point, {Place? named, double? zoom}) {
    setState(() {
      _center = point;
      _named = named;
      _results = null;
    });
    _map.move(point.latLng, zoom ?? _map.camera.zoom);
  }

  Future<void> _myLocation() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _goTo(await widget.location!.current(), zoom: 14);
    } on LocationUnavailable catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The place under the pin. A hand-placed pin is named by asking what's
  /// there, once, now (not on every pan).
  Future<void> _confirm() async {
    final point = widget.areaOnly ? _center.rounded(2) : _center;
    var place = _named;
    if (place == null) {
      setState(() => _busy = true);
      try {
        place = await widget.search.reverse(point);
      } on Exception {
        place = null; // still usable, just unnamed
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(Place(
      name: widget.areaOnly ? _areaName(place) : (place?.name ?? 'Dropped pin'),
      address: widget.areaOnly ? null : place?.address,
      point: point,
    ));
  }

  /// "Indiranagar, Bengaluru" out of a full address: an area, not a street.
  String _areaName(Place? place) {
    if (place == null) return 'Pinned area';
    final parts = (place.address ?? place.name).split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    // OpenStreetMap addresses run small to big: "12, 100 Feet Road, Indiranagar, Bengaluru, Karnataka, 560038, India".
    // Skip the house number and road; keep the next two (neighbourhood, city).
    final named = parts.where((p) => !RegExp(r'^\d').hasMatch(p)).toList();
    if (named.length >= 4) return '${named[named.length - 4]}, ${named[named.length - 3]}'.replaceAll(RegExp(r'\s+'), ' ');
    return named.isEmpty ? place.name : named.take(2).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _results;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: widget.areaOnly ? 'Search for a neighbourhood or town' : 'Search for a place or address',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(tooltip: 'Search', icon: const Icon(Icons.arrow_forward), onPressed: _search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          Expanded(
            child: Stack(
              children: [
                PlaceMap(
                  tiles: widget.tiles,
                  controller: _map,
                  center: _center,
                  zoom: widget.areaOnly ? 12 : 15,
                  onMoved: (p) => setState(() {
                    _center = p;
                    _named = null;
                  }),
                ),
                // The pin stays in the middle; the map moves under it.
                IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 40), // tip on the centre, not the icon's middle
                      child: Icon(Icons.location_on, size: 40, color: theme.colorScheme.primary),
                    ),
                  ),
                ),
                if (results != null)
                  Material(
                    elevation: 2,
                    child: results.isEmpty
                        ? const ListTile(title: Text('Nothing found. Try other words, or move the map.'))
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final r in results)
                                ListTile(
                                  leading: const Icon(Icons.place_outlined),
                                  title: Text(r.name),
                                  subtitle: r.address == null ? null : Text(r.address!, maxLines: 2, overflow: TextOverflow.ellipsis),
                                  onTap: () => _goTo(r.point, named: r, zoom: widget.areaOnly ? 13 : 16),
                                ),
                            ],
                          ),
                  ),
                if (widget.location != null)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: FloatingActionButton.small(
                      heroTag: null,
                      tooltip: 'My location',
                      onPressed: _busy ? null : _myLocation,
                      child: const Icon(Icons.my_location),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.areaOnly)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Only the area is shared (to about a kilometre), never an exact address.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _confirm,
                    icon: const Icon(Icons.check),
                    label: Text(_named != null && !widget.areaOnly ? 'Use ${_named!.name}' : (widget.areaOnly ? 'Use this area' : 'Use this spot')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
