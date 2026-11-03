import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_media/shared_media.dart';

const mb = 1024 * 1024;

/// A phone video still on the device, to be compressed before upload.
PickedMedia onPhone({required int sizeBytes, int durationMs = 20000}) => PickedMedia.notLoaded(
      sourcePath: '/videos/clip.mp4',
      contentType: 'video/mp4',
      sizeBytes: sizeBytes,
      durationMs: durationMs,
    );

PickedMedia loaded({required int sizeBytes, int durationMs = 20000}) =>
    PickedMedia(bytes: Uint8List(sizeBytes), contentType: 'video/mp4', durationMs: durationMs);

void main() {
  test('a phone video up to 100 MB is accepted, since it will be compressed', () {
    expect(MediaLimits.problemWith(onPhone(sizeBytes: 42 * mb)), isNull);
    expect(MediaLimits.problemWith(onPhone(sizeBytes: 100 * mb)), isNull);
  });

  test('a phone video over 100 MB is refused before compressing', () {
    expect(MediaLimits.problemWith(onPhone(sizeBytes: 180 * mb)), 'This video is 180 MB; pick one under 100 MB');
  });

  test('a video over 30 seconds is refused, whatever its size', () {
    expect(MediaLimits.problemWith(onPhone(sizeBytes: 5 * mb, durationMs: 45000)),
        'Videos can be at most 30 seconds (this one is 0:45)');
    expect(MediaLimits.problemWith(onPhone(sizeBytes: 5 * mb, durationMs: 30000)), isNull);
  });

  test('after compressing, the result must still fit the server\'s 50 MB', () {
    expect(MediaLimits.problemWith(loaded(sizeBytes: 49 * mb)), isNull);
    expect(MediaLimits.problemWith(loaded(sizeBytes: 60 * mb)), 'Still over 50 MB after compressing; try a shorter clip');
  });

  test('in a browser (no compressing) the original itself must fit 50 MB', () {
    final browserVideo = PickedMedia.notLoaded(sourcePath: null, contentType: 'video/mp4', sizeBytes: 70 * mb, durationMs: 10000);
    expect(MediaLimits.problemWith(browserVideo), 'Videos can be at most 50 MB (this one is 70 MB)');
  });

  test('a video whose length couldn\'t be read is refused', () {
    final unknown = PickedMedia.notLoaded(sourcePath: '/v.mp4', contentType: 'video/mp4', sizeBytes: mb);
    expect(MediaLimits.problemWith(unknown), 'Couldn\'t read this video\'s length');
  });
}
