import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'browser_upload_stub.dart' if (dart.library.js_interop) 'browser_upload_web.dart';
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
  /// Pass [httpClient] to force the package:http path (tests do, on any
  /// platform). Otherwise a browser uses XMLHttpRequest, for real progress.
  MediaUploader({http.Client? httpClient, this.chunkSize = 64 * 1024}) : _injectedHttp = httpClient;

  final http.Client? _injectedHttp;
  late final http.Client _http = _injectedHttp ?? http.Client();
  final int chunkSize;

  /// [onProgress] gets 0..1 as the file goes out.
  Future<void> upload(UploadTicket ticket, Uint8List bytes, {void Function(double progress)? onProgress}) async {
    final status = kIsWeb && _injectedHttp == null
        ? await browserUpload(ticket.uploadUrl, ticket.method, ticket.headers, bytes, onProgress)
        : await _uploadWithHttp(ticket, bytes, onProgress);
    if (status < 200 || status >= 300) throw UploadFailedException(status);
  }

  /// Progress here is bytes handed to the connection, which on mobile and
  /// desktop tracks what's actually sent closely enough.
  Future<int> _uploadWithHttp(
    UploadTicket ticket,
    Uint8List bytes,
    void Function(double progress)? onProgress,
  ) async {
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
    return result.statusCode;
  }
}
