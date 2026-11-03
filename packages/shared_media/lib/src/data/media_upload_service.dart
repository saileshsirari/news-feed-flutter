import '../models/media_attachment.dart';
import '../models/picked_media.dart';
import 'media_api.dart';
import 'media_uploader.dart';

/// The three-step upload for one file: ask our server for a link, send the
/// bytes to the bucket, tell our server it's done. No UI state; that's
/// MediaDraftNotifier's job.
class MediaUploadService {
  MediaUploadService(this._api, this._uploader);

  final MediaApi _api;
  final MediaUploader _uploader;

  Future<MediaAttachment> upload(PickedMedia media, {void Function(double progress)? onProgress}) async {
    final ticket = await _api.requestUpload(media);
    await _uploader.upload(ticket, media.bytes, onProgress: onProgress);
    return _api.completeUpload(ticket.mediaId);
  }
}
