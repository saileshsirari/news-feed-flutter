import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:geo_kit/geo_kit.dart';
import 'package:intl/intl.dart';
import 'package:shared_media/shared_media.dart';

import '../data/services/api_service.dart';
import '../geo/geo_services.dart';
import 'event.dart';
import 'event_screen.dart';
import 'events_api.dart';
import 'events_providers.dart';

/// Creating an event in a community, or (organisers) editing one.
///
/// Times are picked on this device's clock and sent as instants; the event
/// is labelled with this device's time zone (e.g. Asia/Kolkata), which is
/// how other people see "its" time. Editing keeps the zone it was made in.
class EditEventScreen extends ConsumerStatefulWidget {
  const EditEventScreen({super.key, required this.communityId, this.event});

  final int communityId;

  /// Null when creating.
  final Event? event;

  static Future<void> create(BuildContext context, int communityId) => Navigator.of(context).push(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => EditEventScreen(communityId: communityId)),
      );

  static Future<void> edit(BuildContext context, Event event) => Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => EditEventScreen(communityId: event.communityId, event: event),
        ),
      );

  @override
  ConsumerState<EditEventScreen> createState() => _EditEventScreenState();
}

class _EditEventScreenState extends ConsumerState<EditEventScreen> {
  late final _title = TextEditingController(text: widget.event?.title ?? '');
  late final _description = TextEditingController(text: widget.event?.description ?? '');
  late final _place = TextEditingController(text: widget.event?.placeName ?? '');
  late final _address = TextEditingController(text: widget.event?.address ?? '');
  late final _url = TextEditingController(text: widget.event?.onlineUrl ?? '');
  late final _capacity = TextEditingController(text: widget.event?.capacity?.toString() ?? '');

  late bool _online = widget.event?.isOnline ?? false;

  /// Where on the map, for "events near me" (null: not pinned).
  late GeoPoint? _point = switch (widget.event) {
    Event(:final double latitude, :final double longitude) => GeoPoint(latitude, longitude),
    _ => null,
  };
  late bool _limited = widget.event?.capacity != null;
  late DateTime _start = widget.event?.localStart ?? _nextHour(DateTime.now().add(const Duration(days: 1)));
  late Duration _length =
      widget.event == null ? const Duration(hours: 2) : widget.event!.endsAt.difference(widget.event!.startsAt);
  String? _timeZone;

  Uint8List? _coverBytes;
  Future<int>? _coverUpload;
  bool _saving = false;
  String? _error;

  bool get _creating => widget.event == null;

  static DateTime _nextHour(DateTime t) => DateTime(t.year, t.month, t.day, t.hour + 1);

  @override
  void initState() {
    super.initState();
    _timeZone = widget.event?.timeZone;
    if (_timeZone == null) {
      FlutterTimezone.getLocalTimezone().then((tz) {
        if (mounted) setState(() => _timeZone = tz.identifier);
      }).catchError((Object _) {
        if (mounted) setState(() => _timeZone = 'UTC');
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _place, _address, _url, _capacity]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _start.isBefore(now) ? now : _start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked != null) {
      setState(() => _start = DateTime(picked.year, picked.month, picked.day, _start.hour, _start.minute));
    }
  }

  Future<void> _pickTime({required bool end}) async {
    final current = end ? _start.add(_length) : _start;
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (picked == null) return;
    setState(() {
      if (end) {
        var finish = DateTime(_start.year, _start.month, _start.day, picked.hour, picked.minute);
        // Ending "earlier" than it starts means the next day (a late-night event).
        if (!finish.isAfter(_start)) finish = finish.add(const Duration(days: 1));
        _length = finish.difference(_start);
      } else {
        _start = DateTime(_start.year, _start.month, _start.day, picked.hour, picked.minute);
      }
    });
  }

  Future<void> _pickCover() async {
    final picked = await ref.read(mediaPickerProvider).pickPhoto(maxSide: 1600);
    if (picked == null || !mounted) return;
    setState(() {
      _coverBytes = picked.bytes;
      _coverUpload = ref.read(mediaUploadServiceProvider).upload(picked).then((m) => m.id);
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final problem = switch (null) {
      _ when title.characters.length < 3 => 'Give it a title of at least 3 characters.',
      _ when _online && !_url.text.trim().startsWith('https://') => 'An online event needs an https:// link.',
      _ when !_online && _place.text.trim().length < 2 => 'Say where it is.',
      _ when _limited && (int.tryParse(_capacity.text.trim()) ?? 0) < 1 => 'Spots must be a number, at least 1.',
      _ when _timeZone == null => 'Still finding your time zone; try again in a moment.',
      _ => null,
    };
    if (problem != null) return setState(() => _error = problem);

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final draft = EventDraft(
        title: title,
        description: _description.text,
        startsAt: _start.toUtc(),
        endsAt: _start.add(_length).toUtc(),
        timeZone: _timeZone!,
        online: _online,
        placeName: _place.text,
        address: _address.text,
        point: _point,
        onlineUrl: _url.text.trim(),
        capacity: _limited ? int.parse(_capacity.text.trim()) : null,
        coverMediaId: await _coverUpload,
      );
      final api = ref.read(eventsApiProvider);
      final event = widget.event;
      if (event == null) {
        final created = await api.create(widget.communityId, draft);
        ref.invalidate(communityEventsProvider((communityId: widget.communityId, past: false)));
        ref.invalidate(upcomingEventsProvider);
        if (!mounted) return;
        Navigator.of(context).pop();
        await EventScreen.open(context, created.id);
      } else {
        ref.read(eventProvider(event.id).notifier).show(await api.update(event.id, draft));
        if (mounted) Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _reason(e));
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t save. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _reason(ApiException e) {
    if (e.isRateLimited) return 'Too many changes for now. Try again in a minute.';
    try {
      return (jsonDecode(e.body) as Map<String, dynamic>)['error'] as String? ?? 'Couldn\'t save (${e.statusCode}).';
    } on Object {
      return 'Couldn\'t save (${e.statusCode}).';
    }
  }

  /// Choose the spot; a searched place also fills in the place and address.
  Future<void> _pinOnMap() async {
    final point = _point;
    final place = await pickPlace(
      context,
      search: ref.read(placeSearchProvider),
      tiles: ref.read(mapTilesProvider),
      location: ref.read(locationSourceProvider),
      initial: point == null ? null : Place(name: _place.text.trim().isEmpty ? 'Pinned spot' : _place.text.trim(), point: point),
      title: 'Where is it?',
    );
    if (place == null || !mounted) return;
    setState(() {
      _point = place.point;
      if (_place.text.trim().isEmpty && place.name != 'Dropped pin') _place.text = place.name;
      if (_address.text.trim().isEmpty && place.address != null) _address.text = place.address!;
    });
  }

  @override
  Widget build(BuildContext context) {
    final end = _start.add(_length);
    final day = DateFormat('EEE d MMM y');
    final time = DateFormat('HH:mm');
    final cover = _coverBytes;
    final existing = widget.event?.cover;

    return Scaffold(
      appBar: AppBar(
        title: Text(_creating ? 'New event' : 'Edit event'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_creating ? 'Create' : 'Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          InkWell(
            onTap: _saving ? null : _pickCover,
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: cover != null
                    ? Image.memory(cover, fit: BoxFit.cover)
                    : existing != null
                        ? MediaImage(
                            MediaAttachment(
                              id: existing.id,
                              kind: MediaKind.image,
                              url: existing.url,
                              contentType: 'image/jpeg',
                              sizeBytes: 0,
                            ),
                          )
                        : ColoredBox(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            child: const Center(child: Text('Add a cover photo')),
                          ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            maxLength: 100,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_outlined),
            title: Text(day.format(_start)),
            onTap: _pickDate,
          ),
          Row(
            children: [
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: Text('Starts ${time.format(_start)}'),
                  onTap: () => _pickTime(end: false),
                ),
              ),
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Ends ${time.format(end)}${end.day != _start.day ? ' (next day)' : ''}',
                  ),
                  onTap: () => _pickTime(end: true),
                ),
              ),
            ],
          ),
          Text(
            'Time zone: ${_timeZone ?? 'finding…'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.place_outlined), label: Text('In person')),
              ButtonSegment(value: true, icon: Icon(Icons.videocam_outlined), label: Text('Online')),
            ],
            selected: {_online},
            onSelectionChanged: (s) => setState(() => _online = s.first),
          ),
          const SizedBox(height: 12),
          if (_online)
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Meeting link (https://…)',
                helperText: 'Only people going see it.',
                border: OutlineInputBorder(),
              ),
            )
          else ...[
            TextField(
              controller: _place,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Place', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _address,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Address (optional)', border: OutlineInputBorder()),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_point == null ? Icons.add_location_alt_outlined : Icons.location_on),
              title: Text(_point == null ? 'Pin it on the map' : 'Pinned on the map'),
              subtitle: Text(_point == null ? 'So people nearby find it, and can get directions.' : 'Tap to move the pin.'),
              trailing: _point == null
                  ? null
                  : IconButton(tooltip: 'Remove pin', icon: const Icon(Icons.close), onPressed: () => setState(() => _point = null)),
              onTap: _saving ? null : _pinOnMap,
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Limit spots'),
            subtitle: const Text('When it\'s full, people join a waitlist.'),
            value: _limited,
            onChanged: (v) => setState(() => _limited = v),
          ),
          if (_limited)
            TextField(
              controller: _capacity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Spots', border: OutlineInputBorder()),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLength: 2000,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(labelText: 'What to expect', border: OutlineInputBorder()),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }
}
