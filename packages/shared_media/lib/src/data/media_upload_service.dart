import 'dart:typed_data';

import '../models/media_attachment.dart';
import '../models/picked_media.dart';
import '../models/sealed_attachment.dart';
import '../processing/jpeg_encoder_io.dart' if (dart.library.js_interop) '../processing/jpeg_encoder_web.dart';
import '../sealed/local_media.dart';
import '../sealed/media_sealer.dart';
import 'media_api.dart';
import 'media_uploader.dart';

/// The upload for one file: ask our server for a link, send the bytes to
/// the bucket (a video's poster first), tell our server it's done. No UI
/// state; that's MediaDraftNotifier's job.
class MediaUploadService {
  MediaUploadService(this._api, this._uploader);

  final MediaApi _api;
  final MediaUploader _uploader;

  /// A sealed file's preview: tiny (a few KB), since it rides inside the
  /// encrypted message, but enough to show something while the file loads.
  static const previewMaxSide = 120;
  static const previewQuality = 55;

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

  /// For an end-to-end encrypted chat: encrypts [media] with [sealer] and
  /// uploads only that. What the file is (and its key) comes back, for the
  /// encrypted message. A video's poster isn't uploaded at all; a tiny
  /// preview goes in the message instead.
  Future<SealedAttachment> uploadSealed(
    PickedMedia media,
    MediaSealer sealer, {
    void Function(double progress)? onProgress,
  }) async {
    final preview = await _preview(media);
    final sealed = await sealer.seal(media.bytes);
    final ticket = await _api.requestSealedUpload(sealed.ciphertext.length);
    await _uploader.upload(ticket, sealed.ciphertext, onProgress: onProgress);
    await _api.completeSealedUpload(ticket.mediaId);
    final attachment = SealedAttachment(
      mediaId: ticket.mediaId,
      key: sealed.key,
      kind: media.kind!,
      contentType: media.contentType,
      sizeBytes: media.sizeBytes,
      width: media.width,
      height: media.height,
      durationMs: media.durationMs,
      preview: preview,
    );
    // Already here, decrypted: the sender never downloads their own.
    await keepOpened(attachment, media.bytes, poster: media.thumbnail);
    return attachment;
  }

  static Future<Uint8List?> _preview(PickedMedia media) async {
    final source = media.kind == MediaKind.video ? media.thumbnail : media.bytes;
    if (source == null) return null;
    try {
      return await encodePreviewJpeg(source, previewMaxSide, previewQuality);
    } catch (_) {
      return null; // shown without one
    }
  }
}

/// Keeps [attachment]'s decrypted [bytes] (and a video's [poster]) on this
/// device, as the attachment the usual widgets show.
Future<MediaAttachment> keepOpened(SealedAttachment attachment, Uint8List bytes, {Uint8List? poster}) async {
  final url = await keepLocal('media-${attachment.mediaId}', bytes, attachment.contentType);
  final posterBytes = poster ?? attachment.preview;
  final posterUrl = attachment.kind == MediaKind.video && posterBytes != null
      ? await keepLocal('poster-${attachment.mediaId}', posterBytes, 'image/jpeg')
      : null;
  return attachment.opened(url, posterUrl: posterUrl);
}

/// [attachment] as already kept on this device, or null.
Future<MediaAttachment?> findOpened(SealedAttachment attachment) async {
  final url = await findLocal('media-${attachment.mediaId}', attachment.contentType);
  if (url == null) return null;
  return attachment.opened(url, posterUrl: await findLocal('poster-${attachment.mediaId}', 'image/jpeg'));
}
