import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_media/src/processing/image_shrinker.dart';
import 'package:shared_media/shared_media.dart';

/// A screenshot-sized PNG with enough detail (noise) to be well over the
/// threshold, optionally with a fully transparent top-left corner.
Uint8List largePng({bool transparentCorner = false}) {
  final random = Random(1);
  final image = img.Image(width: 860, height: 1920, numChannels: 4);
  for (final p in image) {
    final see = transparentCorner && p.x < 100 && p.y < 100;
    p
      ..r = random.nextInt(256)
      ..g = (p.y ~/ 8) % 256
      ..b = 120
      ..a = see ? 0 : 255;
  }
  return img.encodePng(image);
}

PickedMedia png(Uint8List bytes) => PickedMedia(bytes: bytes, contentType: 'image/png', width: 860, height: 1920);

void main() {
  test('re-encodes a large PNG as a smaller JPEG of the same size', () async {
    final original = largePng();
    expect(original.length, greaterThan(ImageShrinker.pngThresholdBytes));

    final shrunk = await ImageShrinker.shrink(png(original));

    expect(shrunk.contentType, 'image/jpeg');
    expect(shrunk.sizeBytes, lessThan(original.length));
    expect((shrunk.width, shrunk.height), (860, 1920));
    final decoded = img.decodeJpg(shrunk.bytes)!;
    expect((decoded.width, decoded.height), (860, 1920));
  });

  test('flattens transparency onto white, not black', () async {
    final shrunk = await ImageShrinker.shrink(png(largePng(transparentCorner: true)));
    final corner = img.decodeJpg(shrunk.bytes)!.getPixel(10, 10);
    expect([corner.r, corner.g, corner.b], everyElement(greaterThan(245)));
  });

  test('leaves small PNGs, JPEGs and undecodable files alone', () async {
    final small = img.encodePng(img.Image(width: 10, height: 10));
    final smallPng = png(small);
    expect(await ImageShrinker.shrink(smallPng), same(smallPng));

    final jpeg = PickedMedia(bytes: Uint8List(600 * 1024), contentType: 'image/jpeg');
    expect(await ImageShrinker.shrink(jpeg), same(jpeg));

    final garbage = png(Uint8List(600 * 1024));
    expect(await ImageShrinker.shrink(garbage), same(garbage));
  });
}
