import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

/// Phones and desktops: decrypted files go in the app's cache folder (the
/// system may clear it; they're downloaded and decrypted again then).
Directory get _folder => Directory('${Directory.systemTemp.path}/e2e_media');

File _file(String name, String contentType) => File('${_folder.path}/$name.${contentType.split('/').last}');

Future<Uri?> findLocal(String name, String contentType) async {
  final file = _file(name, contentType);
  return await file.exists() ? file.uri : null;
}

Future<Uri> keepLocal(String name, Uint8List bytes, String contentType) async {
  final file = _file(name, contentType);
  await file.parent.create(recursive: true);
  // Written beside it first, so a half-written file is never found.
  final partial = File('${file.path}.part');
  await partial.writeAsBytes(bytes, flush: true);
  await partial.rename(file.path);
  return file.uri;
}

/// An image from this device, or null if [url] is on the network.
ImageProvider? localImage(Uri url) => url.isScheme('file') ? FileImage(File(url.toFilePath())) : null;

VideoPlayerController videoControllerFor(Uri url) =>
    url.isScheme('file') ? VideoPlayerController.file(File(url.toFilePath())) : VideoPlayerController.networkUrl(url);
