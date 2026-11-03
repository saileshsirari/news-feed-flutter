import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_media/shared_media.dart';

/// Records what was uploaded where; fails PUTs to [failing] urls.
class FakeUploader implements MediaUploader {
  final uploads = <(Uri, int)>[];
  final failing = <Uri>{};

  @override
  Future<void> upload(SignedUpload ticket, Uint8List bytes, {void Function(double progress)? onProgress}) async {
    uploads.add((ticket.uploadUrl, bytes.length));
    if (failing.contains(ticket.uploadUrl)) throw UploadFailedException(500);
  }

  @override
  int get chunkSize => 0;
}

class FakeApi implements MediaApi {
  FakeApi(this.ticket);

  final UploadTicket ticket;
  int? completed;

  @override
  Future<UploadTicket> requestUpload(PickedMedia media) async => ticket;

  @override
  Future<MediaAttachment> completeUpload(int mediaId) async {
    completed = mediaId;
    return MediaAttachment.fromJson({
      'id': mediaId,
      'kind': 'video',
      'contentType': 'video/mp4',
      'sizeBytes': 100,
      'durationMs': 5000,
      'url': 'https://bucket.test/v.mp4',
      'thumbnailUrl': 'https://bucket.test/v.thumb.jpg',
    });
  }
}

final videoUrl = Uri.parse('https://bucket.test/put/v.mp4');
final posterUrl = Uri.parse('https://bucket.test/put/v.thumb.jpg');

UploadTicket videoTicket() => UploadTicket.fromJson({
      'mediaId': 9,
      'uploadUrl': videoUrl.toString(),
      'method': 'PUT',
      'headers': {'Content-Type': 'video/mp4'},
      'thumbnail': {'uploadUrl': posterUrl.toString(), 'method': 'PUT', 'headers': {'Content-Type': 'image/jpeg'}},
    });

PickedMedia video({Uint8List? thumbnail}) => PickedMedia(
      bytes: Uint8List(100),
      contentType: 'video/mp4',
      durationMs: 5000,
      thumbnail: thumbnail,
    );

void main() {
  test('parses a video ticket\'s poster link', () {
    final ticket = videoTicket();
    expect(ticket.thumbnail!.uploadUrl, posterUrl);
    expect(ticket.thumbnail!.headers, {'Content-Type': 'image/jpeg'});
    expect(UploadTicket.fromJson({'mediaId': 1, 'uploadUrl': 'https://x', 'method': 'PUT', 'headers': {}}).thumbnail,
        isNull);
  });

  test('uploads the poster before the video, then completes', () async {
    final uploader = FakeUploader();
    final api = FakeApi(videoTicket());

    final attachment = await MediaUploadService(api, uploader).upload(video(thumbnail: Uint8List(20)));

    expect(uploader.uploads, [(posterUrl, 20), (videoUrl, 100)]);
    expect(api.completed, 9);
    expect(attachment.thumbnailUrl, Uri.parse('https://bucket.test/v.thumb.jpg'));
  });

  test('a failed poster upload doesn\'t stop the video', () async {
    final uploader = FakeUploader()..failing.add(posterUrl);
    final api = FakeApi(videoTicket());

    await MediaUploadService(api, uploader).upload(video(thumbnail: Uint8List(20)));

    expect(uploader.uploads.last, (videoUrl, 100));
    expect(api.completed, 9);
  });

  test('a video without a poster uploads just the video', () async {
    final uploader = FakeUploader();
    await MediaUploadService(FakeApi(videoTicket()), uploader).upload(video());
    expect(uploader.uploads, [(videoUrl, 100)]);
  });

  test('accepts iPhone .mov videos and rejects oversized ones without loading them', () {
    expect(MediaPicker.contentTypeFor('IMG_0042.MOV', null), 'video/quicktime');
    expect(
      MediaLimits.problemWith(PickedMedia(bytes: Uint8List(10), contentType: 'video/quicktime', durationMs: 4000)),
      isNull,
    );

    final huge = PickedMedia.tooLarge(contentType: 'video/mp4', sizeBytes: 300 * 1024 * 1024);
    expect(huge.bytes, isEmpty);
    expect(huge.sizeBytes, 300 * 1024 * 1024);
    expect(MediaLimits.problemWith(huge), 'Videos can be at most 50 MB');
  });
}
