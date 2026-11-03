import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Uploads with XMLHttpRequest instead of package:http, because only XHR
/// reports upload progress in a browser: package:http hands the whole body
/// to the browser at once, so its progress jumps to 100% and then sits
/// there for the whole upload. Returns the HTTP status (0 if the request
/// never got a response, e.g. offline or blocked by CORS).
Future<int> browserUpload(
  Uri url,
  String method,
  Map<String, String> headers,
  Uint8List bytes,
  void Function(double progress)? onProgress,
) {
  final done = Completer<int>();
  final xhr = web.XMLHttpRequest()..open(method, url.toString());
  headers.forEach((name, value) => xhr.setRequestHeader(name, value));
  xhr.upload.onprogress = ((web.ProgressEvent event) {
    if (event.lengthComputable && event.total > 0) onProgress?.call(event.loaded / event.total);
  }).toJS;
  xhr.onload = ((web.Event _) => done.complete(xhr.status)).toJS;
  xhr.onerror = ((web.Event _) => done.complete(0)).toJS;
  xhr.send(bytes.toJS);
  return done.future;
}
