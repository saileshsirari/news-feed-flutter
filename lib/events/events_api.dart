import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:geo_kit/geo_kit.dart';

import '../config/app_config.dart';
import '../data/services/api_service.dart' show ApiException;
import '../data/services/service_providers.dart';
import '../session/current_user_provider.dart';
import 'event.dart';

/// A page of results and where the next one starts (null: no more).
typedef EventPage<T> = ({List<T> items, String? nextCursor});

/// What an organiser fills in. Times are instants (UTC); [timeZone] is the
/// event's own clock.
class EventDraft {
  const EventDraft({
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.timeZone,
    required this.online,
    this.description,
    this.placeName,
    this.address,
    this.point,
    this.onlineUrl,
    this.capacity,
    this.coverMediaId,
  });

  final String title;
  final String? description;
  final DateTime startsAt;
  final DateTime endsAt;
  final String timeZone;
  final bool online;
  final String? placeName;
  final String? address;

  /// Where on the map (for "events near me"); null: not pinned.
  final GeoPoint? point;
  final String? onlineUrl;

  /// Null: no limit.
  final int? capacity;
  final int? coverMediaId;

  Map<String, Object?> toJson() => {
        'title': title,
        'description': description,
        'startsAt': startsAt.millisecondsSinceEpoch,
        'endsAt': endsAt.millisecondsSinceEpoch,
        'timeZone': timeZone,
        'location': online
            ? {'kind': 'online', 'onlineUrl': onlineUrl}
            : {
                'kind': 'in_person',
                'placeName': placeName,
                'address': address,
                'latitude': point?.lat,
                'longitude': point?.lng,
              },
        'capacity': capacity,
        'coverMediaId': ?coverMediaId,
      };
}

/// The server's events routes, as the signed-in [userId] (only read under
/// development login; a real login is trusted from its token).
class EventsApi {
  EventsApi(this._config, this._http, {required this.userId});

  final AppConfig _config;
  final http.Client _http;
  final int userId;

  Uri _uri(String path, [Map<String, Object?> query = const {}]) =>
      Uri.parse('${_config.apiBaseUrl}$path').replace(queryParameters: {
        'userId': '$userId',
        for (final MapEntry(:key, :value) in query.entries)
          if (value != null) key: '$value',
      });

  Future<Object?> _send(String method, Uri uri, [Map<String, Object?>? body]) async {
    final request = http.Request(method, uri);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final res = await http.Response.fromStream(await _http.send(request));
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
    return res.statusCode == 204 || res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
  }

  Event _event(Object? json) => Event.fromJson(json! as Map<String, dynamic>);

  EventPage<Event> _events(Object? json) {
    final map = json! as Map<String, dynamic>;
    return (
      items: [for (final e in map['items'] as List) Event.fromJson(e as Map<String, dynamic>)],
      nextCursor: map['nextCursor'] as String?,
    );
  }

  Future<Event> get(int id) async => _event(await _send('GET', _uri('/events/$id')));

  Future<Event> create(int communityId, EventDraft draft) async =>
      _event(await _send('POST', _uri('/communities/$communityId/events'), draft.toJson()));

  Future<Event> update(int id, EventDraft draft) async => _event(await _send('PATCH', _uri('/events/$id'), draft.toJson()));

  Future<Event> cancel(int id) async => _event(await _send('POST', _uri('/events/$id/cancel')));

  /// Going, or the waitlist when it's full.
  Future<Event> rsvp(int id) async => _event(await _send('PUT', _uri('/events/$id/rsvp')));

  Future<Event> unrsvp(int id) async => _event(await _send('DELETE', _uri('/events/$id/rsvp')));

  Future<EventPage<Event>> forCommunity(int communityId, {bool past = false, String? cursor}) async => _events(
        await _send('GET', _uri('/communities/$communityId/events', {'when': past ? 'past' : 'upcoming', 'cursor': cursor})),
      );

  /// Coming up across every community you're in.
  Future<EventPage<Event>> upcoming({String? cursor}) async =>
      _events(await _send('GET', _uri('/events/upcoming', {'cursor': cursor})));

  /// Still to come within [radiusKm] of [near], nearest first (each with
  /// its distanceKm). [near] should already be rounded (geo_kit's
  /// DeviceLocation does): the server only needs "around here".
  Future<List<Event>> nearby(GeoPoint near, {double radiusKm = 10}) async => [
        for (final e in (await _send('GET', _uri('/events/nearby', {'lat': near.lat, 'lng': near.lng, 'radiusKm': radiusKm})))!
            as List)
          Event.fromJson(e as Map<String, dynamic>),
      ];

  Future<EventPage<EventAttendee>> attendees(int id, {RsvpStatus status = RsvpStatus.going, String? cursor}) async {
    final json = (await _send('GET', _uri('/events/$id/attendees', {'status': status.name, 'cursor': cursor})))!
        as Map<String, dynamic>;
    return (
      items: [for (final a in json['items'] as List) EventAttendee.fromJson(a as Map<String, dynamic>)],
      nextCursor: json['nextCursor'] as String?,
    );
  }
}

final eventsApiProvider = Provider<EventsApi>(
  (ref) => EventsApi(
    ref.watch(appConfigProvider),
    ref.watch(apiHttpClientProvider),
    userId: ref.watch(currentUserProvider).requireValue!.id,
  ),
);
