import '../formatting.dart';
import 'media_attachment.dart';
import 'picked_media.dart';

/// What can be uploaded, checked on the device so a bad pick fails at once
/// with a clear reason instead of after a long upload.
///
/// The final limits mirror the server's (src/modules/media/mediaPolicy.ts),
/// which checks again; keep the two in step. The original-video limit is
/// the app's own: a phone compresses before uploading, so it can take a
/// bigger original than the server would, as long as the result fits.
abstract final class MediaLimits {
  static const allowedContentTypes = {'image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/quicktime'};
  static const maxImageBytes = 10 * 1024 * 1024;

  /// What the server accepts — after compressing, when there is any.
  static const maxVideoBytes = 50 * 1024 * 1024;

  /// The biggest original a phone will try to compress down to [maxVideoBytes].
  static const maxOriginalVideoBytes = 100 * 1024 * 1024;

  static const maxVideoDurationMs = 30000;

  /// Why [media] can't be uploaded, or null if it can. A video still on the
  /// device (to be compressed) is held to [maxOriginalVideoBytes]; once
  /// loaded, or on web where nothing is compressed, to [maxVideoBytes].
  static String? problemWith(PickedMedia media) {
    if (!allowedContentTypes.contains(media.contentType)) return 'This file type isn\'t supported';
    if (media.sizeBytes == 0) return 'This file is empty';
    final durationMs = media.durationMs ?? -1;
    return switch (media.kind!) {
      MediaKind.image when media.sizeBytes > maxImageBytes => 'Images can be at most ${_mb(maxImageBytes)}',
      MediaKind.image => null,
      MediaKind.video when durationMs < 0 => 'Couldn\'t read this video\'s length',
      MediaKind.video when durationMs > maxVideoDurationMs =>
        'Videos can be at most ${maxVideoDurationMs ~/ 1000} seconds (this one is ${formatVideoDuration(durationMs)})',
      MediaKind.video when media.needsPreparing && media.sizeBytes > maxOriginalVideoBytes =>
        'This video is ${_mb(media.sizeBytes)}; pick one under ${_mb(maxOriginalVideoBytes)}',
      MediaKind.video when !media.needsPreparing && media.sizeBytes > maxVideoBytes => media.isLoaded
          ? 'Still over ${_mb(maxVideoBytes)} after compressing; try a shorter clip'
          : 'Videos can be at most ${_mb(maxVideoBytes)} (this one is ${_mb(media.sizeBytes)})',
      MediaKind.video => null,
    };
  }

  static String _mb(int bytes) => '${(bytes / (1024 * 1024)).round()} MB';
}
