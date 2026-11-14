import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:geo_kit/geo_kit.dart';

import '../config/app_config.dart';
import '../data/services/api_service.dart' show ApiException;
import '../data/services/service_providers.dart';
import '../models/models.dart';
import '../session/current_user_provider.dart';
import 'community.dart';

/// The server's /communities routes, as the signed-in [userId] (the server
/// trusts the login; [userId] is only read under development login).
class CommunitiesApi {
  CommunitiesApi(this._config, this._http, {required this.userId});

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

  CommunityPage<Community> _communities(Object? json) {
    final map = json! as Map<String, dynamic>;
    return (
      items: [for (final c in map['items'] as List) Community.fromJson(c as Map<String, dynamic>)],
      nextCursor: map['nextCursor'] as String?,
    );
  }

  /// Biggest first; with [query], those whose name or description has it.
  Future<CommunityPage<Community>> discover({String? query, String? cursor}) async =>
      _communities(await _send('GET', _uri('/communities', {'query': query, 'cursor': cursor})));

  /// The ones you're in, most recently joined first.
  Future<CommunityPage<Community>> joined({String? cursor}) async =>
      _communities(await _send('GET', _uri('/communities/joined', {'cursor': cursor})));

  Future<Community> get(int id) async =>
      Community.fromJson((await _send('GET', _uri('/communities/$id')))! as Map<String, dynamic>);

  Future<Community> create({
    required String name,
    String? description,
    required CommunityVisibility visibility,
    int? photoMediaId,
    Place? area,
  }) async =>
      Community.fromJson((await _send('POST', _uri('/communities'), {
        'name': name,
        'description': description,
        'visibility': visibility.name,
        'photoMediaId': ?photoMediaId,
        'area': ?_area(area),
      }))! as Map<String, dynamic>);

  static Map<String, Object?>? _area(Place? area) =>
      area == null ? null : {'name': area.name, 'lat': area.point.lat, 'lng': area.point.lng};

  /// Communities based within [radiusKm] of [near], nearest first.
  Future<List<Community>> nearby(GeoPoint near, {double radiusKm = 10}) async => [
        for (final c in (await _send('GET', _uri('/communities/nearby', {'lat': near.lat, 'lng': near.lng, 'radiusKm': radiusKm})))!
            as List)
          Community.fromJson(c as Map<String, dynamic>),
      ];

  /// Owner only. Only what's given changes; [removePhoto] clears the photo.
  Future<Community> update(
    int id, {
    String? name,
    String? description,
    CommunityVisibility? visibility,
    int? photoMediaId,
    bool removePhoto = false,
    Place? area,
    bool removeArea = false,
  }) async =>
      Community.fromJson((await _send('PATCH', _uri('/communities/$id'), {
        'name': ?name,
        'description': ?description,
        'visibility': ?visibility?.name,
        if (removePhoto) 'photoMediaId': null else 'photoMediaId': ?photoMediaId,
        if (removeArea) 'area': null else 'area': ?_area(area),
      }))! as Map<String, dynamic>);

  Future<void> delete(int id) => _send('DELETE', _uri('/communities/$id'));

  /// Public: you're in. Private: you've asked.
  Future<Community> join(int id) async =>
      Community.fromJson((await _send('POST', _uri('/communities/$id/join')))! as Map<String, dynamic>);

  /// Leaving, or taking back a request.
  Future<Community> leave(int id) async =>
      Community.fromJson((await _send('DELETE', _uri('/communities/$id/membership')))! as Map<String, dynamic>);

  Future<CommunityPage<CommunityMember>> members(
    int id, {
    MembershipStatus status = MembershipStatus.active,
    String? cursor,
  }) async {
    final json = (await _send('GET', _uri('/communities/$id/members', {'status': status.name, 'cursor': cursor})))!
        as Map<String, dynamic>;
    return (
      items: [for (final m in json['items'] as List) CommunityMember.fromJson(m as Map<String, dynamic>)],
      nextCursor: json['nextCursor'] as String?,
    );
  }

  /// The community's posts, newest first.
  Future<FeedPage> posts(int id, {String? cursor}) async =>
      FeedPage.fromJson((await _send('GET', _uri('/communities/$id/posts', {'cursor': cursor})))! as Map<String, dynamic>);

  /// Moderators: a link that lets people in, for [expiresInHours] (null:
  /// for good) and [maxUses] people (null: any number).
  Future<CommunityInvite> createInvite(int id, {int? expiresInHours, int? maxUses}) async =>
      CommunityInvite.fromJson((await _send('POST', _uri('/communities/$id/invites'), {
        'expiresInHours': ?expiresInHours,
        'maxUses': ?maxUses,
      }))! as Map<String, dynamic>);

  /// Moderators: the links that still work.
  Future<List<CommunityInvite>> invites(int id) async => [
        for (final i in (await _send('GET', _uri('/communities/$id/invites')))! as List)
          CommunityInvite.fromJson(i as Map<String, dynamic>),
      ];

  Future<void> revokeInvite(int id, String code) => _send('DELETE', _uri('/communities/$id/invites/$code'));

  Future<InvitePreview> previewInvite(String code) async =>
      InvitePreview.fromJson((await _send('GET', _uri('/invites/$code')))! as Map<String, dynamic>);

  /// Joins with it: straight in, even a private community.
  Future<Community> acceptInvite(String code) async =>
      Community.fromJson((await _send('POST', _uri('/invites/$code/accept')))! as Map<String, dynamic>);

  /// Members: a notification when a new event is planned here, or not.
  Future<Community> setEventNotifications(int id, {required bool on}) async =>
      Community.fromJson((await _send('PUT', _uri('/communities/$id/notifications'), {'events': on}))! as Map<String, dynamic>);

  /// The community's group chat (made the first time a member opens it).
  Future<int> chat(int id) async =>
      ((await _send('POST', _uri('/communities/$id/chat')))! as Map<String, dynamic>)['conversationId'] as int;

  Future<void> approve(int id, int memberId) => _send('POST', _uri('/communities/$id/members/$memberId/approve'));

  /// Owner only: moderator or member.
  Future<void> setRole(int id, int memberId, CommunityRole role) =>
      _send('PUT', _uri('/communities/$id/members/$memberId/role'), {'role': role.name});

  /// Removes a member, declines a request or lifts a ban; with [ban], they can't come back.
  Future<void> removeMember(int id, int memberId, {bool ban = false}) =>
      _send('DELETE', _uri('/communities/$id/members/$memberId', {'ban': ban ? 'true' : null}));
}

final communitiesApiProvider = Provider<CommunitiesApi>(
  (ref) => CommunitiesApi(
    ref.watch(appConfigProvider),
    ref.watch(apiHttpClientProvider),
    userId: ref.watch(currentUserProvider).requireValue!.id,
  ),
);
