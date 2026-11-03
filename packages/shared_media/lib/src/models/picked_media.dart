import 'dart:typed_data';

import 'media_attachment.dart';

/// A file the user picked, not uploaded yet. Usually its bytes are in
/// memory (so it works the same on web); a video on a phone starts as just
/// a path, and VideoPreparer loads (and compresses) it before upload.
class PickedMedia {
  const PickedMedia({
    required this.bytes,
    required this.contentType,
    this.width,
    this.height,
    this.durationMs,
    this.thumbnail,
  })  : sourcePath = null,
        _declaredSizeBytes = null;

  /// Not read into memory yet: a long phone video can be hundreds of MB,
  /// and reading it just to check limits or compress it could run the app
  /// out of memory. [sourcePath] null means it can't be read later either
  /// (a browser video over the limit), so it can only be rejected.
  PickedMedia.notLoaded({
    required this.sourcePath,
    required this.contentType,
    required int sizeBytes,
    this.width,
    this.height,
    this.durationMs,
    this.thumbnail,
  })  : bytes = Uint8List(0),
        _declaredSizeBytes = sizeBytes;

  final Uint8List bytes;
  final String contentType;
  final int? width;
  final int? height;
  final int? durationMs;

  /// A video's JPEG poster, made on the device; null for images, or if one
  /// couldn't be made.
  final Uint8List? thumbnail;

  /// Where a not-yet-loaded file is on the device.
  final String? sourcePath;

  final int? _declaredSizeBytes;

  bool get isLoaded => _declaredSizeBytes == null;

  /// Can still be loaded (and so compressed) before upload.
  bool get needsPreparing => !isLoaded && sourcePath != null;

  int get sizeBytes => _declaredSizeBytes ?? bytes.length;

  MediaKind? get kind => switch (contentType.split('/').first) {
        'image' => MediaKind.image,
        'video' => MediaKind.video,
        _ => null,
      };
}
