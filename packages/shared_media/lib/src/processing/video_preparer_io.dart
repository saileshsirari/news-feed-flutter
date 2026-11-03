import 'dart:io';

import 'package:video_compress/video_compress.dart';

import '../models/picked_media.dart';
import 'video_preparer.dart';

/// Phones: compress to 720p with the platform's hardware encoder (via
/// video_compress), then read the result. If compressing fails or doesn't
/// help, the original is used instead, so a video never fails to post just
/// because it couldn't be shrunk.
class PlatformVideoPreparer implements VideoPreparer {
  /// Smaller clips are already quick to upload; not worth the wait.
  static const compressAboveBytes = 8 * 1024 * 1024;

  /// video_compress runs one job at a time and throws if asked for a
  /// second, so several picked videos take turns.
  static Future<void> _queue = Future.value();

  @override
  Future<PickedMedia> prepare(PickedMedia media, {void Function(double progress)? onProgress}) {
    final path = media.sourcePath;
    if (!media.needsPreparing || path == null) return Future.value(media);
    if (media.sizeBytes <= compressAboveBytes) return _load(media, path, path, media.contentType);

    final result = _queue.then((_) => _compress(media, path, onProgress));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<PickedMedia> _compress(PickedMedia media, String path, void Function(double progress)? onProgress) async {
    final progress = VideoCompress.compressProgress$.subscribe((percent) => onProgress?.call(percent / 100));
    MediaInfo? compressed;
    try {
      compressed = await VideoCompress.compressVideo(path, quality: VideoQuality.Res1280x720Quality, includeAudio: true);
    } catch (_) {
      compressed = null;
    } finally {
      progress.unsubscribe();
    }

    final output = compressed?.path;
    final helped = output != null && (compressed!.filesize ?? 1 << 62) < media.sizeBytes;
    if (!helped) return _load(media, path, path, media.contentType);
    return _load(
      media,
      output,
      path,
      'video/mp4', // compressed output is always MP4, even from an iPhone .mov
      width: compressed.width,
      height: compressed.height,
    );
  }

  /// Reads [file] as the upload, deleting it afterwards if it's a
  /// compressed copy rather than the user's original at [originalPath].
  Future<PickedMedia> _load(
    PickedMedia media,
    String file,
    String originalPath,
    String contentType, {
    int? width,
    int? height,
  }) async {
    final bytes = await File(file).readAsBytes();
    if (file != originalPath) File(file).delete().ignore();
    return PickedMedia(
      bytes: bytes,
      contentType: contentType,
      width: width ?? media.width,
      height: height ?? media.height,
      durationMs: media.durationMs,
      thumbnail: media.thumbnail,
    );
  }
}
