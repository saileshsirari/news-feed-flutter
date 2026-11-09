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

/// A small JPEG of [image] (any format the decoder knows), its longer side
/// at most [maxSide]; null if it can't be decoded.
Future<Uint8List?> encodePreviewJpeg(Uint8List image, int maxSide, int quality) =>
    compute(_preview, (image, maxSide, quality));

Uint8List? _preview((Uint8List, int, int) args) {
  final (bytes, maxSide, quality) = args;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final small = decoded.width >= decoded.height
      ? img.copyResize(decoded, width: decoded.width < maxSide ? decoded.width : maxSide)
      : img.copyResize(decoded, height: decoded.height < maxSide ? decoded.height : maxSide);
  return img.encodeJpg(small, quality: quality);
}
