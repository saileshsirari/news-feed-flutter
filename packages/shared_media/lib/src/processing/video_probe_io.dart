import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:video_player/video_player.dart';

import 'video_probe.dart';

/// Mobile and desktop: video_player reads the length and size (it opens the
/// file without playing it), and the platform's own decoder makes the
/// poster. A failed poster still returns the length, so the video uploads.
Future<VideoInfo?> probeVideo(String path, int thumbnailMaxSide, int thumbnailQuality) async {
  final controller = VideoPlayerController.file(File(path));
  final Duration duration;
  final Size size;
  try {
    await controller.initialize();
    duration = controller.value.duration;
    size = controller.value.size;
  } finally {
    await controller.dispose();
  }

  Uint8List? thumbnail;
  try {
    thumbnail = await FcNativeVideoThumbnail().saveThumbnailToBytes(
      srcFile: path,
      width: thumbnailMaxSide,
      height: thumbnailMaxSide,
      quality: thumbnailQuality,
    );
  } catch (_) {
    thumbnail = null;
  }

  return VideoInfo(
    durationMs: duration.inMilliseconds,
    width: size.width > 0 ? size.width.round() : null,
    height: size.height > 0 ? size.height.round() : null,
    thumbnail: thumbnail,
  );
}
