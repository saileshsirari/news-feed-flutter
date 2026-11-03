import 'dart:typed_data';

/// Only reached in a browser; see browser_upload_web.dart.
Future<int> browserUpload(
  Uri url,
  String method,
  Map<String, String> headers,
  Uint8List bytes,
  void Function(double progress)? onProgress,
) =>
    throw UnsupportedError('browserUpload is only available on web');
