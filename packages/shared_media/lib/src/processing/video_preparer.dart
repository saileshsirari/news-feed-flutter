import '../models/picked_media.dart';
import '../settings/video_upload_quality.dart';
import 'video_preparer_io.dart' if (dart.library.js_interop) 'video_preparer_web.dart' as platform;

/// Turns a picked video that's still only a path on the device into bytes
/// ready to upload, compressing it first to the user's chosen quality where
/// the platform can. A recorded phone clip is often 15+ Mbit/s; compressed
/// it's a fraction of the size and much faster to upload.
abstract interface class VideoPreparer {
  /// [onProgress] gets 0..1 while compressing. Returns [media] unchanged if
  /// there's nothing to prepare (already loaded, e.g. on web).
  Future<PickedMedia> prepare(
    PickedMedia media, {
    required VideoUploadQuality quality,
    void Function(double progress)? onProgress,
  });

  /// This platform's: hardware compression on phones, none in a browser.
  factory VideoPreparer() = platform.PlatformVideoPreparer;
}
