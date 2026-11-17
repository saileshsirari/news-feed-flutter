import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../data/services/api_service.dart' show ApiException;
import 'org.dart';

/// The server's /orgs and /org-invites routes. These are about the person,
/// not one organisation, so they go without an X-Org header (see
/// [OrgHeaderClient]); [userId] is only read under development login.
class OrgsApi {
  OrgsApi(this._config, this._http, {required this.userId});

  final AppConfig _config;
  final http.Client _http;
  final int userId;

  Uri _uri(String path) => Uri.parse('${_config.apiBaseUrl}$path').replace(queryParameters: {'userId': '$userId'});

  Future<Object?> _send(String method, String path, [Map<String, Object?>? body]) async {
    final request = http.Request(method, _uri(path));
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({...body, 'userId': userId});
    }
    final res = await http.Response.fromStream(await _http.send(request));
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
    return res.statusCode == 204 || res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
  }

  /// The organisations I'm in, oldest membership first.
  Future<List<Org>> mine() async {
    final json = (await _send('GET', '/orgs'))! as Map<String, dynamic>;
    return [for (final o in json['orgs'] as List) Org.fromJson(o as Map<String, dynamic>)];
  }

  /// Owners and admins: a new invite link.
  Future<OrgInvite> createInvite(int orgId, {int? expiresInHours, int? maxUses, String? email}) async =>
      OrgInvite.fromJson(
        (await _send('POST', '/orgs/$orgId/invites', {
              'expiresInHours': ?expiresInHours,
              'maxUses': ?maxUses,
              'email': ?email,
            }))!
            as Map<String, dynamic>,
      );

  /// Owners and admins: the links that still work.
  Future<List<OrgInvite>> invites(int orgId) async {
    final json = (await _send('GET', '/orgs/$orgId/invites'))! as Map<String, dynamic>;
    return [for (final i in json['invites'] as List) OrgInvite.fromJson(i as Map<String, dynamic>)];
  }

  Future<void> revokeInvite(int orgId, String code) => _send('DELETE', '/orgs/$orgId/invites/$code');

  /// Which organisation an invite is for, and whether it still works.
  Future<OrgInvitePreview> previewInvite(String code) async =>
      OrgInvitePreview.fromJson((await _send('GET', '/org-invites/$code'))! as Map<String, dynamic>);

  /// Joins with an invite; returns the organisation.
  Future<Org> acceptInvite(String code) async =>
      Org.fromJson((await _send('POST', '/org-invites/$code/accept', {}))! as Map<String, dynamic>);
}
