import '../models/picked_media.dart';
import '../settings/video_upload_quality.dart';
import 'video_preparer.dart';

/// Browsers have no practical built-in video encoder, so web uploads the
/// video as picked (MediaPicker loads it, within the server's limit),
/// whatever quality is chosen.
class PlatformVideoPreparer implements VideoPreparer {
  @override
  Future<PickedMedia> prepare(
    PickedMedia media, {
    required VideoUploadQuality quality,
    void Function(double progress)? onProgress,
  }) async =>
      media;
}
