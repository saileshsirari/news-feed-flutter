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
  });

  final Uint8List bytes;
  final String contentType;
  final int? width;
  final int? height;
  final int? durationMs;

  int get sizeBytes => bytes.length;

  MediaKind? get kind => switch (contentType.split('/').first) {
        'image' => MediaKind.image,
        'video' => MediaKind.video,
        _ => null,
      };
}
