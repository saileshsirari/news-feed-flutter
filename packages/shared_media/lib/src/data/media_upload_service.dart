import '../models/media_attachment.dart';
import '../models/picked_media.dart';
import 'media_api.dart';
import 'media_uploader.dart';

/// The upload for one file: ask our server for a link, send the bytes to
/// the bucket (a video's poster first), tell our server it's done. No UI
/// state; that's MediaDraftNotifier's job.
class MediaUploadService {
  MediaUploadService(this._api, this._uploader);

  final MediaApi _api;
  final MediaUploader _uploader;

  Future<MediaAttachment> upload(PickedMedia media, {void Function(double progress)? onProgress}) async {
    final ticket = await _api.requestUpload(media);
    final thumbnailUpload = ticket.thumbnail;
    final thumbnail = media.thumbnail;
    if (thumbnailUpload != null && thumbnail != null) {
      try {
        await _uploader.upload(thumbnailUpload, thumbnail);
      } catch (_) {
        // Optional: the video still posts, just without a poster image.
      }
    }
    await _uploader.upload(ticket, media.bytes, onProgress: onProgress);
    return _api.completeUpload(ticket.mediaId);
  }
}
