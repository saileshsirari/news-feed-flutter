import 'package:flutter/foundation.dart';

import '../models/picked_media.dart';
import 'jpeg_encoder_io.dart' if (dart.library.js_interop) 'jpeg_encoder_web.dart';

/// Re-encodes large PNGs (screenshots, mostly) as JPEG before upload. The
/// picker's own resizing doesn't help them: a phone screenshot is already
/// within its size limit, and its quality setting only affects JPEGs, so
/// they went up at 1–3 MB and took many seconds on a slow connection.
///
/// Small PNGs are left alone: they're cheap to upload, and are the ones
/// most likely to rely on transparency (stickers, logos), which JPEG can't
/// keep.
abstract final class ImageShrinker {
  static const pngThresholdBytes = 500 * 1024;

  /// High enough that text in screenshots stays crisp.
  static const jpegQuality = 85;

  static Future<PickedMedia> shrink(PickedMedia media) async {
    if (media.contentType != 'image/png' || media.sizeBytes <= pngThresholdBytes) return media;
    final Uint8List? jpeg;
    try {
      jpeg = await encodeAsJpeg(media.bytes, jpegQuality);
    } catch (_) {
      return media; // can't re-encode it here; uploading the original still works
    }
    if (jpeg == null || jpeg.length >= media.sizeBytes) return media;
    return PickedMedia(bytes: jpeg, contentType: 'image/jpeg', width: media.width, height: media.height);
  }
}
