import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/media_attachment.dart';
import '../models/picked_media.dart';

/// A signed link to PUT one file's bytes to.
class SignedUpload {
  const SignedUpload({required this.uploadUrl, required this.method, required this.headers});

  factory SignedUpload.fromJson(Map<String, dynamic> json) => SignedUpload(
    uploadUrl: Uri.parse(json['uploadUrl'] as String),
    method: json['method'] as String,
    headers: (json['headers'] as Map).cast<String, String>(),
  );

  final Uri uploadUrl;
  final String method;

  /// Must be sent exactly, or the signed link is rejected.
  final Map<String, String> headers;
}

/// Where to upload one file, from `POST /media/uploads`.
class UploadTicket extends SignedUpload {
  const UploadTicket({
    required this.mediaId,
    required super.uploadUrl,
    required super.method,
    required super.headers,
    this.thumbnail,
  });

  factory UploadTicket.fromJson(Map<String, dynamic> json) {
    final file = SignedUpload.fromJson(json);
    return UploadTicket(
      mediaId: json['mediaId'] as int,
      uploadUrl: file.uploadUrl,
      method: file.method,
      headers: file.headers,
      thumbnail: switch (json['thumbnail']) {
        final Map<String, dynamic> t => SignedUpload.fromJson(t),
        _ => null,
      },
    );
  }

  final int mediaId;

  /// Videos only: where to put the poster image, before completing.
  final SignedUpload? thumbnail;
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

  /// For a file encrypted on the device (see MediaSealer): the server is
  /// told its size and nothing else.
  Future<UploadTicket> requestSealedUpload(int sizeBytes);
  Future<void> completeSealedUpload(int mediaId);
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

  /// Just bytes to the server: no type, size in pixels or length.
  @override
  Future<UploadTicket> requestSealedUpload(int sizeBytes) async => UploadTicket.fromJson(
    await _post('/media/uploads', {'userId': userId, 'contentType': sealedContentType, 'sizeBytes': sizeBytes}),
  );

  @override
  Future<void> completeSealedUpload(int mediaId) => _post('/media/$mediaId/complete', {'userId': userId});

  static const sealedContentType = 'application/octet-stream';

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final res = await _http.post(
      baseUrl.resolve(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode == 429) {
      // From the body, not the Retry-After header: a browser hides that
      // header from cross-origin code.
      final wait = _field(res.body, 'retryAfterSeconds');
      throw MediaApiException(429, 'Too many uploads for now. Try again${wait == null ? ' later' : ' in $wait s'}.');
    }
    if (res.statusCode >= 400) throw MediaApiException(res.statusCode, _errorMessage(res.body));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Object? _field(String body, String name) {
    try {
      return (jsonDecode(body) as Map<String, dynamic>)[name];
    } on Object {
      return null;
    }
  }

  static String _errorMessage(String body) {
    try {
      return (jsonDecode(body) as Map<String, dynamic>)['error'] as String? ?? body;
    } on FormatException {
      return body;
    }
  }
}
