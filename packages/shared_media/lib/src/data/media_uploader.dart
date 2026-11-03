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

/// Sends a file's bytes straight to the bucket using a signed link (an
/// [UploadTicket], or its thumbnail's). Knows nothing about our API server.
class MediaUploader {
  /// Pass [httpClient] to force the package:http path (tests do, on any
  /// platform). Otherwise a browser uses XMLHttpRequest, for real progress.
  MediaUploader({http.Client? httpClient, this.chunkSize = 64 * 1024}) : _injectedHttp = httpClient;

  final http.Client? _injectedHttp;
  late final http.Client _http = _injectedHttp ?? http.Client();
  final int chunkSize;

  /// [onProgress] gets 0..1 as the file goes out.
  Future<void> upload(SignedUpload ticket, Uint8List bytes, {void Function(double progress)? onProgress}) async {
    final status = kIsWeb && _injectedHttp == null
        ? await browserUpload(ticket.uploadUrl, ticket.method, ticket.headers, bytes, onProgress)
        : await _uploadWithHttp(ticket, bytes, onProgress);
    if (status < 200 || status >= 300) throw UploadFailedException(status);
  }

  Future<int> _uploadWithHttp(
    SignedUpload ticket,
    Uint8List bytes,
    void Function(double progress)? onProgress,
  ) async {
    final request = _ProgressRequest(ticket, bytes, chunkSize, onProgress);
    final result = await _http.send(request);
    await result.stream.drain<void>();
    return result.statusCode;
  }
}

/// A PUT whose body is pulled a chunk at a time, reporting progress as each
/// chunk is taken. The connection only takes the next chunk once it has
/// room to send it, so progress follows what has actually gone out —
/// pushing every chunk in at once (as http.StreamedRequest invites) would
/// report 100% before the upload had really started.
class _ProgressRequest extends http.BaseRequest {
  _ProgressRequest(SignedUpload ticket, this._bytes, this._chunkSize, this._onProgress)
      : super(ticket.method, ticket.uploadUrl) {
    headers.addAll(ticket.headers);
    contentLength = _bytes.length;
  }

  final Uint8List _bytes;
  final int _chunkSize;
  final void Function(double progress)? _onProgress;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_chunks());
  }

  Stream<List<int>> _chunks() async* {
    for (var start = 0; start < _bytes.length; start += _chunkSize) {
      final end = start + _chunkSize < _bytes.length ? start + _chunkSize : _bytes.length;
      yield Uint8List.sublistView(_bytes, start, end);
      // Resumes only when the connection asks for more, i.e. this chunk is on its way.
      _onProgress?.call(end / _bytes.length);
    }
  }
}
