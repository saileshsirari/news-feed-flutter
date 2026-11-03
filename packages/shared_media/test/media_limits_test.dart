import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_media/shared_media.dart';

PickedMedia media(String contentType, int size, {int? durationMs}) =>
    PickedMedia(bytes: Uint8List(size), contentType: contentType, durationMs: durationMs);

void main() {
  test('accepts files the server allows', () {
    expect(MediaLimits.problemWith(media('image/jpeg', 1000)), isNull);
    expect(MediaLimits.problemWith(media('video/mp4', 1000, durationMs: 30000)), isNull);
  });

  test('explains what is wrong with a file it rejects', () {
    expect(MediaLimits.problemWith(media('image/gif', 10)), contains('type'));
    expect(MediaLimits.problemWith(media('image/png', 0)), contains('empty'));
    expect(MediaLimits.problemWith(media('image/png', MediaLimits.maxImageBytes + 1)), contains('10 MB'));
    expect(MediaLimits.problemWith(media('video/mp4', 10)), contains('length'));
    expect(MediaLimits.problemWith(media('video/mp4', 10, durationMs: 30001)), contains('30 seconds'));
  });
}
