import '../models/picked_media.dart';
import 'video_preparer_io.dart' if (dart.library.js_interop) 'video_preparer_web.dart' as platform;

/// Turns a picked video that's still only a path on the device into bytes
/// ready to upload, compressing it first where the platform can. A
/// recorded phone clip is often 15+ Mbit/s; at 720p it's a fraction of the
/// size and much faster to upload, and still sharp on a phone screen.
abstract interface class VideoPreparer {
  /// [onProgress] gets 0..1 while compressing. Returns [media] unchanged if
  /// there's nothing to prepare (already loaded, e.g. on web).
  Future<PickedMedia> prepare(PickedMedia media, {void Function(double progress)? onProgress});

  /// This platform's: hardware compression on phones, none in a browser.
  factory VideoPreparer() = platform.PlatformVideoPreparer;
}
