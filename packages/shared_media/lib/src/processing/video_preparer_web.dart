import '../models/picked_media.dart';
import 'video_preparer.dart';

/// Browsers have no practical built-in video encoder, so web uploads the
/// video as picked (MediaPicker loads it, within the server's limit).
class PlatformVideoPreparer implements VideoPreparer {
  @override
  Future<PickedMedia> prepare(PickedMedia media, {void Function(double progress)? onProgress}) async => media;
}
