import 'dart:typed_data';

import 'media_attachment.dart';

/// A file the user picked, already compressed if it's going to be, and not
/// uploaded yet. Bytes in memory rather than a file path so it works the
/// same on web.
class PickedMedia {
  const PickedMedia({
    required this.bytes,
    required this.contentType,
    this.width,
    this.height,
    this.durationMs,
    this.thumbnail,
  }) : _declaredSizeBytes = null;

  /// A file too big to upload, recorded by size only: reading a long phone
  /// video into memory just to reject it could run the app out of memory.
  /// MediaLimits turns it into a "too large" message.
  PickedMedia.tooLarge({required this.contentType, required int sizeBytes})
      : bytes = Uint8List(0),
        width = null,
        height = null,
        durationMs = null,
        thumbnail = null,
        _declaredSizeBytes = sizeBytes;

  final Uint8List bytes;
  final String contentType;
  final int? width;
  final int? height;
  final int? durationMs;

  /// A video's JPEG poster, made on the device; null for images, or if one
  /// couldn't be made.
  final Uint8List? thumbnail;

  final int? _declaredSizeBytes;

  int get sizeBytes => _declaredSizeBytes ?? bytes.length;

  MediaKind? get kind => switch (contentType.split('/').first) {
        'image' => MediaKind.image,
        'video' => MediaKind.video,
        _ => null,
      };
}
