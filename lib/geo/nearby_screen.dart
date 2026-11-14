import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geo_kit/geo_kit.dart';

import '../communities/communities_api.dart';
import '../communities/communities_screen.dart' show CommunityTile;
import '../communities/community.dart';
import '../communities/community_screen.dart';
import '../events/event.dart';
import '../events/event_screen.dart';
import '../events/event_tile.dart';
import '../events/events_api.dart';
import 'geo_services.dart';

/// A "near me" search: around which point, and how far.
typedef NearbyQuery = ({GeoPoint near, double radiusKm});

final nearbyEventsProvider = FutureProvider.autoDispose.family<List<Event>, NearbyQuery>(
  (ref, q) => ref.watch(eventsApiProvider).nearby(q.near, radiusKm: q.radiusKm),
);

final nearbyCommunitiesProvider = FutureProvider.autoDispose.family<List<Community>, NearbyQuery>(
  (ref, q) => ref.watch(communitiesApiProvider).nearby(q.near, radiusKm: q.radiusKm),
);

enum _Showing { events, communities }

/// Events and communities around you (or around a place you choose), as a
/// list or on a map.
///
/// Your location is asked for only when this screen opens, only roughly
/// (to about a kilometre), and isn't kept anywhere: the server uses it for
/// this one search.
class NearbyScreen extends ConsumerStatefulWidget {
  const NearbyScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NearbyScreen()));

  static const radiiKm = [2.0, 5.0, 10.0, 25.0, 50.0];

  @override
  ConsumerState<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends ConsumerState<NearbyScreen> {
  GeoPoint? _near;

  /// "Your area", or the place chosen instead.
  String _nearName = 'Your area';
  double _radiusKm = 10;
  var _showing = _Showing.events;
  bool _onMap = false;

  bool _locating = true;
  LocationUnavailable? _noLocation;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _noLocation = null;
    });
    try {
      final here = await ref.read(locationSourceProvider).current();
      if (mounted) {
        setState(() {
          _near = here;
          _nearName = 'Your area';
        });
      }
    } on LocationUnavailable catch (e) {
      if (mounted) setState(() => _noLocation = e);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _choosePlace() async {
    final place = await pickPlace(
      context,
      search: ref.read(placeSearchProvider),
      tiles: ref.read(mapTilesProvider),
      near: _near,
      title: 'Search around…',
    );
    if (place == null || !mounted) return;
    setState(() {
      _near = place.point;
      _nearName = place.name;
      _noLocation = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final near = _near;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Near me'),
        actions: [
          if (near != null)
            IconButton(
              tooltip: _onMap ? 'Show as a list' : 'Show on a map',
              icon: Icon(_onMap ? Icons.list : Icons.map_outlined),
              onPressed: () => setState(() => _onMap = !_onMap),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SegmentedButton<_Showing>(
              segments: const [
                ButtonSegment(value: _Showing.events, icon: Icon(Icons.event), label: Text('Events')),
                ButtonSegment(value: _Showing.communities, icon: Icon(Icons.groups), label: Text('Communities')),
              ],
              selected: {_showing},
              onSelectionChanged: (s) => setState(() => _showing = s.first),
            ),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.place_outlined),
            title: Text(near == null ? 'Where?' : 'Around $_nearName', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(tooltip: 'Use my location', icon: const Icon(Icons.my_location), onPressed: _locating ? null : _locate),
                TextButton(onPressed: _choosePlace, child: const Text('Change')),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final km in NearbyScreen.radiiKm)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${km.round()} km'),
                      selected: _radiusKm == km,
                      onSelected: (_) => setState(() => _radiusKm = km),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: _body(near)),
        ],
      ),
    );
  }

  Widget _body(GeoPoint? near) {
    if (_locating && near == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Finding your area…')],
        ),
      );
    }
    if (near == null) {
      final problem = _noLocation;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(problem?.message ?? 'Choose where to look.', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _choosePlace, icon: const Icon(Icons.search), label: const Text('Choose a place')),
              if (problem?.fix != null)
                TextButton(onPressed: () => problem!.fix!(), child: const Text('Open settings')),
            ],
          ),
        ),
      );
    }
    final query = (near: near, radiusKm: _radiusKm);
    return switch (_showing) {
      _Showing.events => _Results<Event>(
          value: ref.watch(nearbyEventsProvider(query)),
          retry: () => ref.invalidate(nearbyEventsProvider(query)),
          empty: 'No events within ${_radiusKm.round()} km. Try a wider circle.',
          onMap: _onMap,
          query: query,
          tile: (e) => EventTile(e, showCommunity: true),
          pin: (e) => e.latitude == null || e.longitude == null
              ? null
              : MapPin(point: GeoPoint(e.latitude!, e.longitude!), label: e.title, onTap: () => EventScreen.open(context, e.id)),
        ),
      _Showing.communities => _Results<Community>(
          value: ref.watch(nearbyCommunitiesProvider(query)),
          retry: () => ref.invalidate(nearbyCommunitiesProvider(query)),
          empty: 'No communities based within ${_radiusKm.round()} km.',
          onMap: _onMap,
          query: query,
          tile: CommunityTile.new,
          pin: (c) => c.area == null
              ? null
              : MapPin(point: c.area!.point, label: c.name, onTap: () => CommunityScreen.open(context, c.id)),
        ),
    };
  }
}

/// Loading, failed, empty, a list, or pins on a map.
class _Results<T> extends ConsumerWidget {
  const _Results({
    required this.value,
    required this.retry,
    required this.empty,
    required this.onMap,
    required this.query,
    required this.tile,
    required this.pin,
  });

  final AsyncValue<List<T>> value;
  final VoidCallback retry;
  final String empty;
  final bool onMap;
  final NearbyQuery query;
  final Widget Function(T) tile;
  final MapPin? Function(T) pin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = value.value;
    if (items == null) {
      if (value.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [const Text('Couldn\'t load what\'s nearby.'), TextButton(onPressed: retry, child: const Text('Try again'))],
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (onMap) {
      // Zoomed so the circle fits: 13.5 for 2 km, about 9 for 50 km.
      // Each zoom level halves the distance across the screen, hence log2.
      final zoom = 14.5 - math.log(query.radiusKm.clamp(1, 64)) / math.ln2;
      return PlaceMap(
        key: ValueKey(query),
        tiles: ref.watch(mapTilesProvider),
        center: query.near,
        zoom: zoom,
        radiusKm: query.radiusKm,
        pins: [for (final item in items) ?pin(item)],
      );
    }
    if (items.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(empty, textAlign: TextAlign.center)));
    return RefreshIndicator(
      onRefresh: () async => retry(),
      child: ListView(children: [for (final item in items) tile(item)]),
    );
  }
}
