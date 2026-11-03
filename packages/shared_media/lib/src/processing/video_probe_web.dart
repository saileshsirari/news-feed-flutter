import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'video_probe.dart';

/// Browser: a detached <video> element reads the length and size, then
/// seeks a little way in and draws that frame onto a canvas for the poster.
/// The browser decodes, so whatever it can play, it can probe.
Future<VideoInfo?> probeVideo(String blobUrl, int thumbnailMaxSide, int thumbnailQuality) async {
  final video = web.HTMLVideoElement()
    ..muted = true
    ..preload = 'auto'
    ..src = blobUrl;
  try {
    await _next(video, 'loadedmetadata');
    final durationMs = (video.duration * 1000).round();
    final width = video.videoWidth;
    final height = video.videoHeight;

    Uint8List? thumbnail;
    try {
      // Not frame 0, which is often black (fade-ins); not past the end of a very short clip.
      video.currentTime = min(0.5, video.duration / 2);
      await _next(video, 'seeked');
      thumbnail = await _drawFrame(video, width, height, thumbnailMaxSide, thumbnailQuality);
    } catch (_) {
      thumbnail = null;
    }

    return VideoInfo(
      durationMs: durationMs,
      width: width > 0 ? width : null,
      height: height > 0 ? height : null,
      thumbnail: thumbnail,
    );
  } finally {
    video
      ..removeAttribute('src')
      ..load(); // releases the decoder
  }
}

/// Waits for [event] on [video], failing on a load error or after 10 s.
Future<void> _next(web.HTMLVideoElement video, String event) {
  final done = Completer<void>();
  void finish(Object? error) {
    if (done.isCompleted) return;
    error == null ? done.complete() : done.completeError(error);
  }

  video.addEventListener(event, ((web.Event _) => finish(null)).toJS, web.AddEventListenerOptions(once: true));
  video.addEventListener('error', ((web.Event _) => finish(StateError('video failed to load'))).toJS,
      web.AddEventListenerOptions(once: true));
  return done.future.timeout(const Duration(seconds: 10));
}

Future<Uint8List?> _drawFrame(web.HTMLVideoElement video, int width, int height, int maxSide, int quality) async {
  if (width <= 0 || height <= 0) return null;
  final scale = min(1.0, maxSide / max(width, height));
  final canvas = web.HTMLCanvasElement()
    ..width = (width * scale).round()
    ..height = (height * scale).round();
  (canvas.getContext('2d')! as web.CanvasRenderingContext2D).drawImage(video, 0, 0, canvas.width, canvas.height);

  final done = Completer<web.Blob?>();
  canvas.toBlob(((web.Blob? blob) => done.complete(blob)).toJS, 'image/jpeg', (quality / 100).toJS);
  final blob = await done.future;
  if (blob == null) return null;
  return (await blob.arrayBuffer().toDart).toDart.asUint8List();
}
