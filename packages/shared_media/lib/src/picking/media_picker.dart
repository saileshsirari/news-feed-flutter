import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/media_limits.dart';
import '../models/picked_media.dart';
import '../processing/image_shrinker.dart';
import '../processing/video_probe.dart';

/// Opens the gallery for photos and videos together and returns them ready
/// for upload. Photos are shrunk: image_picker resizes them and recompresses
/// JPEGs (on web too, via a canvas), and ImageShrinker turns large PNGs into
/// JPEGs, which image_picker leaves alone. Videos are uploaded as recorded,
/// with their length, size and a poster image read on the device.
class MediaPicker {
  MediaPicker({ImagePicker? imagePicker}) : _picker = imagePicker ?? ImagePicker();

  final ImagePicker _picker;

  /// Longest side after resizing. Sharp on any phone screen; a full-screen
  /// viewer can still zoom a little.
  static const maxDimension = 1920.0;
  static const jpegQuality = 80;

  /// Empty if the user cancelled.
  Future<List<PickedMedia>> pickMedia({required int limit}) async {
    if (limit <= 0) return const [];
    final files = await _picker.pickMultipleMedia(
      limit: limit >= 2 ? limit : null, // image_picker requires limit >= 2
      maxWidth: maxDimension,
      maxHeight: maxDimension,
      imageQuality: jpegQuality,
    );
    final picked = <PickedMedia>[];
    for (final file in files.take(limit)) {
      final contentType = contentTypeFor(file.name, file.mimeType);
      picked.add(contentType.startsWith('video/') ? await _video(file, contentType) : await _image(file, contentType));
    }
    return picked;
  }

  static Future<PickedMedia> _image(XFile file, String contentType) async {
    final bytes = await file.readAsBytes();
    final size = await _imageSize(bytes);
    return ImageShrinker.shrink(PickedMedia(
      bytes: bytes,
      contentType: contentType,
      width: size?.$1,
      height: size?.$2,
    ));
  }

  static Future<PickedMedia> _video(XFile file, String contentType) async {
    final sizeBytes = await file.length();
    if (sizeBytes > MediaLimits.maxVideoBytes) {
      return PickedMedia.tooLarge(contentType: contentType, sizeBytes: sizeBytes);
    }
    final info = await VideoProbe.probe(file.path);
    return PickedMedia(
      bytes: await file.readAsBytes(),
      contentType: contentType,
      width: info?.width,
      height: info?.height,
      durationMs: info?.durationMs,
      thumbnail: info?.thumbnail,
    );
  }

  /// Width and height, for laying out the image before it loads; null if
  /// the bytes can't be decoded (the upload is then rejected by type anyway).
  static Future<(int, int)?> _imageSize(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = (frame.image.width, frame.image.height);
      frame.image.dispose();
      codec.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  /// image_picker's mimeType is often null on mobile, so fall back to the
  /// file name. Anything unrecognised is passed through and then rejected
  /// with a clear message by MediaLimits.
  @visibleForTesting
  static String contentTypeFor(String fileName, String? mimeType) {
    if (mimeType != null && mimeType.isNotEmpty) return mimeType == 'image/jpg' ? 'image/jpeg' : mimeType;
    final extension = fileName.split('.').last.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'mp4' || 'm4v' => 'video/mp4',
      'mov' => 'video/quicktime',
      _ => 'application/octet-stream',
    };
  }
}
