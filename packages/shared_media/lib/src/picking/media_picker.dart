import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/picked_media.dart';

/// Opens the photo library and returns the chosen images, already shrunk
/// for upload. image_picker does the resizing and JPEG compression itself
/// (on web too, via a canvas), so there's no separate compression step.
class MediaPicker {
  MediaPicker({ImagePicker? imagePicker}) : _picker = imagePicker ?? ImagePicker();

  final ImagePicker _picker;

  /// Longest side after resizing. Sharp on any phone screen; a full-screen
  /// viewer can still zoom a little.
  static const maxDimension = 1920.0;
  static const jpegQuality = 80;

  /// Empty if the user cancelled.
  Future<List<PickedMedia>> pickImages({required int limit}) async {
    if (limit <= 0) return const [];
    final files = await _picker.pickMultiImage(
      limit: limit >= 2 ? limit : null, // image_picker requires limit >= 2
      maxWidth: maxDimension,
      maxHeight: maxDimension,
      imageQuality: jpegQuality,
    );
    final picked = <PickedMedia>[];
    for (final file in files.take(limit)) {
      picked.add(await _toPickedMedia(file));
    }
    return picked;
  }

  static Future<PickedMedia> _toPickedMedia(XFile file) async {
    final bytes = await file.readAsBytes();
    final size = await _imageSize(bytes);
    return PickedMedia(
      bytes: bytes,
      contentType: contentTypeFor(file.name, file.mimeType),
      width: size?.$1,
      height: size?.$2,
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
      'mp4' => 'video/mp4',
      _ => 'application/octet-stream',
    };
  }
}
