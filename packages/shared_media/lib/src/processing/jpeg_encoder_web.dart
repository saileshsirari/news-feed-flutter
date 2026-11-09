import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Browser: let the browser's own image codecs do it on a canvas, which is
/// far faster than decoding in Dart there (no isolates on web, so a Dart
/// encoder would freeze the page). Null if the browser can't decode [png].
Future<Uint8List?> encodeAsJpeg(Uint8List png, int quality) async {
  final blob = web.Blob([png.toJS].toJS, web.BlobPropertyBag(type: 'image/png'));
  final web.ImageBitmap bitmap;
  try {
    bitmap = await web.window.createImageBitmap(blob).toDart;
  } catch (_) {
    return null;
  }

  final canvas = web.HTMLCanvasElement()
    ..width = bitmap.width
    ..height = bitmap.height;
  final context = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
  // JPEG has no transparency; flatten onto white so see-through areas
  // don't turn black.
  context
    ..fillStyle = '#ffffff'.toJS
    ..fillRect(0, 0, bitmap.width, bitmap.height)
    ..drawImage(bitmap, 0, 0);
  bitmap.close();

  final done = Completer<web.Blob?>();
  canvas.toBlob(((web.Blob? result) => done.complete(result)).toJS, 'image/jpeg', (quality / 100).toJS);
  final jpeg = await done.future;
  if (jpeg == null) return null;
  return (await jpeg.arrayBuffer().toDart).toDart.asUint8List();
}

/// A small JPEG of [image], its longer side at most [maxSide], drawn by the
/// browser; null if it can't decode [image].
Future<Uint8List?> encodePreviewJpeg(Uint8List image, int maxSide, int quality) async {
  final web.ImageBitmap bitmap;
  try {
    bitmap = await web.window.createImageBitmap(web.Blob([image.toJS].toJS)).toDart;
  } catch (_) {
    return null;
  }
  final scale = maxSide / (bitmap.width > bitmap.height ? bitmap.width : bitmap.height);
  final factor = scale < 1 ? scale : 1.0;
  final canvas = web.HTMLCanvasElement()
    ..width = (bitmap.width * factor).round()
    ..height = (bitmap.height * factor).round();
  final context = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
  context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  final done = Completer<web.Blob?>();
  canvas.toBlob(((web.Blob? result) => done.complete(result)).toJS, 'image/jpeg', (quality / 100).toJS);
  final jpeg = await done.future;
  if (jpeg == null) return null;
  return (await jpeg.arrayBuffer().toDart).toDart.asUint8List();
}
