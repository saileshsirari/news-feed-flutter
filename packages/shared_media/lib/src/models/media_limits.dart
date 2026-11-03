import 'media_attachment.dart';
import 'picked_media.dart';

/// The server's file rules (src/modules/media/mediaPolicy.ts), checked here
/// too so a bad pick fails at once instead of after a round trip. The
/// server still checks; keep the two in step.
abstract final class MediaLimits {
  static const allowedContentTypes = {'image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/quicktime'};
  static const maxImageBytes = 10 * 1024 * 1024;
  static const maxVideoBytes = 50 * 1024 * 1024;
  static const maxVideoDurationMs = 30000;

  /// Why [media] can't be uploaded, or null if it can.
  static String? problemWith(PickedMedia media) {
    if (!allowedContentTypes.contains(media.contentType)) return 'This file type isn\'t supported';
    if (media.sizeBytes == 0) return 'This file is empty';
    return switch (media.kind!) {
      MediaKind.image when media.sizeBytes > maxImageBytes => 'Images can be at most 10 MB',
      MediaKind.video when media.sizeBytes > maxVideoBytes => 'Videos can be at most 50 MB',
      MediaKind.video when media.durationMs == null => 'Couldn\'t read this video\'s length',
      MediaKind.video when media.durationMs! > maxVideoDurationMs => 'Videos can be at most 30 seconds',
      _ => null,
    };
  }
}
