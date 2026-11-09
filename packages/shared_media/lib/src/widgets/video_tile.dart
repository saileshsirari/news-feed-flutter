import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../formatting.dart';
import '../models/media_attachment.dart';
import '../sealed/local_media.dart';

/// A video in a grid: its poster (or plain dark if it has none), a play
/// button, and its length. Doesn't play; tapping it is the grid's job.
class VideoTile extends StatelessWidget {
  const VideoTile(this.media, {super.key});

  final MediaAttachment media;

  @override
  Widget build(BuildContext context) {
    final poster = media.thumbnailUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black87),
        if (poster != null && localImage(poster) != null)
          Image(image: localImage(poster)!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())
        else if (poster != null)
          CachedNetworkImage(
            imageUrl: poster.toString(),
            // By id, like MediaImage: the signed link changes on every load.
            cacheKey: 'media-poster:${media.id}',
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        const Center(child: PlayBadge()),
        if (media.durationMs != null)
          Positioned(right: 6, bottom: 6, child: DurationBadge(milliseconds: media.durationMs!)),
      ],
    );
  }
}

/// The round ▶ over a video's poster.
class PlayBadge extends StatelessWidget {
  const PlayBadge({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
    child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: size, semanticLabel: 'Play video'),
  );
}

/// A video's length in the corner of its tile.
class DurationBadge extends StatelessWidget {
  const DurationBadge({super.key, required this.milliseconds});

  final int milliseconds;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      child: Text(
        formatVideoDuration(milliseconds),
        style: const TextStyle(color: Colors.white, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
      ),
    ),
  );
}
