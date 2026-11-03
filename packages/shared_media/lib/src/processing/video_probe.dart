import 'dart:typed_data';

import 'video_probe_io.dart' if (dart.library.js_interop) 'video_probe_web.dart' as platform;

/// What the upload needs to know about a video, read on the device.
class VideoInfo {
  const VideoInfo({required this.durationMs, this.width, this.height, this.thumbnail});

  final int durationMs;
  final int? width;
  final int? height;

  /// A JPEG of an early frame, at most [VideoProbe.thumbnailMaxSide] wide
  /// or tall; null if it couldn't be made.
  final Uint8List? thumbnail;
}

abstract final class VideoProbe {
  static const thumbnailMaxSide = 640;
  static const thumbnailQuality = 80;

  /// [path] is what image_picker gave: a file path on mobile and desktop, a
  /// blob URL on web. Null if the video can't be read at all, in which case
  /// MediaLimits rejects it for having no known length.
  static Future<VideoInfo?> probe(String path) async {
    try {
      return await platform.probeVideo(path, thumbnailMaxSide, thumbnailQuality);
    } catch (_) {
      return null;
    }
  }
}
