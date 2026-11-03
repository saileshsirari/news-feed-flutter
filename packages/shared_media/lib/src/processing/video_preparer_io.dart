import 'dart:io';

import 'package:video_compress/video_compress.dart';

import '../models/picked_media.dart';
import '../settings/video_upload_quality.dart';
import 'video_preparer.dart';

/// Phones: compress to the chosen quality with the platform's hardware
/// encoder (via video_compress), then read the result. If compressing fails
/// or doesn't help, the original is used instead, so a video never fails to
/// post just because it couldn't be shrunk.
class PlatformVideoPreparer implements VideoPreparer {
  /// Smaller clips are already quick to upload; not worth the wait.
  static const compressAboveBytes = 8 * 1024 * 1024;

  /// video_compress runs one job at a time and throws if asked for a
  /// second, so several picked videos take turns.
  static Future<void> _queue = Future.value();

  @override
  Future<PickedMedia> prepare(
    PickedMedia media, {
    required VideoUploadQuality quality,
    void Function(double progress)? onProgress,
  }) {
    final path = media.sourcePath;
    if (!media.needsPreparing || path == null) return Future.value(media);
    if (!quality.compresses || media.sizeBytes <= compressAboveBytes) {
      return _load(media, path, path, media.contentType);
    }

    final result = _queue.then((_) => _compress(media, path, _pluginQuality(quality), onProgress));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// "At most" sizes: a smaller original isn't scaled up.
  static VideoQuality _pluginQuality(VideoUploadQuality quality) => switch (quality) {
        VideoUploadQuality.p1080 => VideoQuality.Res1920x1080Quality,
        VideoUploadQuality.p720 => VideoQuality.Res1280x720Quality,
        VideoUploadQuality.p540 => VideoQuality.Res960x540Quality,
        VideoUploadQuality.p480 => VideoQuality.Res640x480Quality,
        VideoUploadQuality.original => throw ArgumentError('original is never compressed'),
      };

  Future<PickedMedia> _compress(
    PickedMedia media,
    String path,
    VideoQuality quality,
    void Function(double progress)? onProgress,
  ) async {
    final progress = VideoCompress.compressProgress$.subscribe((percent) => onProgress?.call(percent / 100));
    MediaInfo? compressed;
    try {
      compressed = await VideoCompress.compressVideo(path, quality: quality, includeAudio: true);
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
