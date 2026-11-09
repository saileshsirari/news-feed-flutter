import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../models/media_attachment.dart';
import '../sealed/local_media.dart';
import 'video_tile.dart';

/// Plays one video full screen: tap to pause or play, drag the bar to seek,
/// × to close. Videos only start here, never on their own in a feed or
/// chat, so scrolling past one costs no data.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.media});

  final MediaAttachment media;

  static Future<void> open(BuildContext context, MediaAttachment media) =>
      Navigator.of(context)
          .push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => VideoPlayerScreen(media: media)));

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  // A decrypted video plays from this device; anything else streams.
  late final VideoPlayerController _controller = videoControllerFor(widget.media.url);
  late final Future<void> _initialized = _controller.initialize().then((_) => _controller.play());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// No setState: the play badge below listens to the controller itself.
  void _togglePlay() => _controller.value.isPlaying ? _controller.pause() : _controller.play();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: FutureBuilder(
                future: _initialized,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text('Couldn\'t play this video', style: TextStyle(color: Colors.white70));
                  }
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const CircularProgressIndicator(color: Colors.white);
                  }
                  return GestureDetector(
                    onTap: _togglePlay,
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(_controller),
                          // Rebuilds as playback starts, stops and ends.
                          ValueListenableBuilder(
                            valueListenable: _controller,
                            builder: (_, value, _) =>
                                value.isPlaying ? const SizedBox.shrink() : const PlayBadge(size: 64),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            // Not for a decrypted video on a phone: it's already on the
            // device, and another app can't open the app's own files.
            if (!widget.media.url.isScheme('file'))
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: const Icon(Icons.download, color: Colors.white),
                  tooltip: 'Download',
                  // The browser (web) or the phone's browser/downloads saves
                  // it; the link is the same short-lived one we play.
                  onPressed: () => launchUrl(widget.media.url, mode: LaunchMode.externalApplication),
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: FutureBuilder(
                future: _initialized,
                builder: (context, snapshot) => snapshot.connectionState == ConnectionState.done && !snapshot.hasError
                    ? VideoProgressIndicator(
                        _controller,
                        allowScrubbing: true,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        colors: const VideoProgressColors(playedColor: Colors.white, bufferedColor: Colors.white38),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
