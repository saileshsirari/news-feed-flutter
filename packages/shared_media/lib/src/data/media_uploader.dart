import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'media_api.dart';

class UploadFailedException implements Exception {
  UploadFailedException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'UploadFailedException($statusCode)';
}

/// Sends a file's bytes straight to the bucket using an [UploadTicket]'s
/// signed link. Knows nothing about our API server.
class MediaUploader {
  MediaUploader({http.Client? httpClient, this.chunkSize = 64 * 1024}) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final int chunkSize;

  /// [onProgress] gets 0..1 as bytes are handed to the connection. On web
  /// the browser sends the body in one go, so it jumps straight to 1.
  Future<void> upload(UploadTicket ticket, Uint8List bytes, {void Function(double progress)? onProgress}) async {
    final request = http.StreamedRequest(ticket.method, ticket.uploadUrl)
      ..headers.addAll(ticket.headers)
      ..contentLength = bytes.length;

    final response = _http.send(request);
    for (var start = 0; start < bytes.length; start += chunkSize) {
      final end = start + chunkSize < bytes.length ? start + chunkSize : bytes.length;
      request.sink.add(bytes.sublist(start, end));
      onProgress?.call(end / bytes.length);
    }
    await request.sink.close();

    final result = await response;
    await result.stream.drain<void>();
    if (result.statusCode >= 300) throw UploadFailedException(result.statusCode);
  }
}
