import 'dart:convert';

import 'package:app_core/config/app_config.dart';
import 'package:app_core/data/services/api_service.dart' show ApiException;
import 'package:app_core/data/services/service_providers.dart';
import 'package:app_core/session/current_user_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geo_kit/geo_kit.dart';
import 'package:http/http.dart' as http;

/// A live share's latest position, as the server or a sealed update says.
class LivePoint {
  const LivePoint({required this.messageId, required this.senderId, required this.point, required this.at});

  final int messageId;
  final int senderId;
  final GeoPoint point;
  final DateTime at;
}

/// The server's live-location routes (its livelocation module).
class LiveLocationApi {
  LiveLocationApi(this._config, this._http, {required this.userId});

  final AppConfig _config;
  final http.Client _http;
  final int userId;

  Uri _uri(String path) => Uri.parse('${_config.apiBaseUrl}$path').replace(queryParameters: {'userId': '$userId'});

  Future<Object?> _send(String method, String path, [Map<String, Object?>? body]) async {
    final request = http.Request(method, _uri(path));
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final res = await http.Response.fromStream(await _http.send(request));
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
    return res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
  }

  /// Normal chats: where I am now, for share [messageId].
  Future<void> update(int conversationId, int messageId, GeoPoint at) =>
      _send('POST', '/conversations/$conversationId/live-location/$messageId', {'lat': at.lat, 'lng': at.lng});

  /// Normal chats: stop share [messageId] early.
  Future<void> stop(int conversationId, int messageId) =>
      _send('POST', '/conversations/$conversationId/live-location/$messageId/stop');

  /// Normal chats: the shares running now, with their latest positions.
  Future<List<LivePoint>> current(int conversationId) async => [
    for (final p in (await _send('GET', '/conversations/$conversationId/live-location'))! as List)
      if ((p as Map)['lat'] != null)
        LivePoint(
          messageId: p['messageId'] as int,
          senderId: p['senderId'] as int,
          point: GeoPoint((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
          at: DateTime.fromMillisecondsSinceEpoch(p['at'] as int),
        ),
  ];

  /// Encrypted chats: a sealed position, passed on unread by the server.
  Future<void> signal(int conversationId, {required int deviceId, required String sealed}) =>
      _send('POST', '/conversations/$conversationId/live-signal', {'deviceId': deviceId, 'ciphertext': sealed});
}

final liveLocationApiProvider = Provider<LiveLocationApi>(
  (ref) => LiveLocationApi(
    ref.watch(appConfigProvider),
    ref.watch(apiHttpClientProvider),
    userId: ref.watch(currentUserProvider).requireValue!.id,
  ),
);
