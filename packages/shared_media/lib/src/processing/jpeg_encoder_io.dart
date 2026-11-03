import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Mobile and desktop: decode and re-encode in pure Dart, on a background
/// isolate so a large screenshot doesn't stall the UI. Null if [png] can't
/// be decoded.
Future<Uint8List?> encodeAsJpeg(Uint8List png, int quality) => compute(_encode, (png, quality));

Uint8List? _encode((Uint8List, int) args) {
  final (png, quality) = args;
  final decoded = img.decodePng(png);
  if (decoded == null) return null;
  // JPEG has no transparency; flatten onto white so see-through areas
  // don't turn black.
  final flat = img.Image(width: decoded.width, height: decoded.height);
  img.fill(flat, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(flat, decoded);
  return img.encodeJpg(flat, quality: quality);
}
