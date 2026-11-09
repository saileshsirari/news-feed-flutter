import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

/// The browser: decrypted files are kept in memory as blob: links for as
/// long as the page is open (downloaded and decrypted again after a reload).
final _links = <String, String>{};

Future<Uri?> findLocal(String name, String contentType) async => switch (_links[name]) {
  final String link => Uri.parse(link),
  null => null,
};

Future<Uri> keepLocal(String name, Uint8List bytes, String contentType) async {
  final link = _links[name] ??= web.URL.createObjectURL(
    web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: contentType)),
  );
  return Uri.parse(link);
}

/// A blob: link is local; the browser loads it like any other.
ImageProvider? localImage(Uri url) => url.isScheme('blob') ? NetworkImage(url.toString()) : null;

VideoPlayerController videoControllerFor(Uri url) => VideoPlayerController.networkUrl(url);
