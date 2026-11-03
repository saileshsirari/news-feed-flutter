import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/media_attachment.dart';
import '../models/picked_media.dart';

/// Where and how to upload one file's bytes, from `POST /media/uploads`.
class UploadTicket {
  const UploadTicket({required this.mediaId, required this.uploadUrl, required this.method, required this.headers});

  factory UploadTicket.fromJson(Map<String, dynamic> json) => UploadTicket(
        mediaId: json['mediaId'] as int,
        uploadUrl: Uri.parse(json['uploadUrl'] as String),
        method: json['method'] as String,
        headers: (json['headers'] as Map<String, dynamic>).cast<String, String>(),
      );

  final int mediaId;
  final Uri uploadUrl;
  final String method;

  /// Must be sent exactly, or the signed link is rejected.
  final Map<String, String> headers;
}

class MediaApiException implements Exception {
  MediaApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'MediaApiException($statusCode): $message';
}

/// The media server's two endpoints. An interface so an app (or a test)
/// can supply its own, e.g. if media moves to a separate service.
abstract interface class MediaApi {
  Future<UploadTicket> requestUpload(PickedMedia media);
  Future<MediaAttachment> completeUpload(int mediaId);
}

/// [MediaApi] over HTTP, acting as [userId] (there's no real auth yet, so
/// the server takes it in the body, like the rest of the API).
class HttpMediaApi implements MediaApi {
  HttpMediaApi({required this.baseUrl, required this.userId, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final Uri baseUrl;
  final int userId;
  final http.Client _http;

  @override
  Future<UploadTicket> requestUpload(PickedMedia media) async {
    final json = await _post('/media/uploads', {
      'userId': userId,
      'contentType': media.contentType,
      'sizeBytes': media.sizeBytes,
      if (media.width != null) 'width': media.width,
      if (media.height != null) 'height': media.height,
      if (media.durationMs != null) 'durationMs': media.durationMs,
    });
    return UploadTicket.fromJson(json);
  }

  @override
  Future<MediaAttachment> completeUpload(int mediaId) async =>
      MediaAttachment.fromJson(await _post('/media/$mediaId/complete', {'userId': userId}));

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final res = await _http.post(
      baseUrl.resolve(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode >= 400) throw MediaApiException(res.statusCode, _errorMessage(res.body));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static String _errorMessage(String body) {
    try {
      return (jsonDecode(body) as Map<String, dynamic>)['error'] as String? ?? body;
    } on FormatException {
      return body;
    }
  }
}
