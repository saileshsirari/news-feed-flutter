import 'package:flutter/material.dart';

import '../models/media_attachment.dart';
import 'media_image.dart';

/// A post's or message's attachments, laid out like most social apps:
/// one file at its own shape, two side by side, three as one large and two
/// small, four or more as a 2×2 grid with "+N" on the last tile.
class MediaGrid extends StatelessWidget {
  const MediaGrid({super.key, required this.media, this.onTap, this.tileBuilder = defaultTile});

  final List<MediaAttachment> media;

  /// Called with the tapped file's index in [media].
  final ValueChanged<int>? onTap;

  /// How one file is drawn; tests swap it to avoid network images.
  final Widget Function(MediaAttachment media) tileBuilder;

  static const _gap = 2.0;
  static const _maxTiles = 4;

  static Widget defaultTile(MediaAttachment media) => switch (media.kind) {
        MediaKind.image => MediaImage(media),
        // Played in phase 4; until then, just show that it's a video.
        MediaKind.video => const _VideoPlaceholder(),
      };

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(aspectRatio: _aspectRatio(), child: _layout()),
    );
  }

  /// A single file keeps its own shape, within limits so a panorama or a
  /// tall screenshot doesn't take over the feed; several share a fixed box.
  double _aspectRatio() {
    if (media.length > 1) return 16 / 10;
    return (media.first.aspectRatio ?? 4 / 3).clamp(3 / 4, 1.91);
  }

  Widget _layout() {
    switch (media.length) {
      case 1:
        return _tile(0);
      case 2:
        return _row([_tile(0), _tile(1)]);
      case 3:
        return _row([_tile(0), _column([_tile(1), _tile(2)])]);
      default:
        return _column([
          _row([_tile(0), _tile(1)]),
          _row([_tile(2), _tile(3, hiddenCount: media.length - _maxTiles)]),
        ]);
    }
  }

  Widget _tile(int index, {int hiddenCount = 0}) {
    return GestureDetector(
      onTap: onTap == null ? null : () => onTap!(index),
      child: Stack(
        fit: StackFit.expand,
        children: [
          tileBuilder(media[index]),
          if (hiddenCount > 0)
            ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Text(
                  '+$hiddenCount',
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Widget _row(List<Widget> children) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _spaced(children, const SizedBox(width: _gap)),
      );

  static Widget _column(List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _spaced(children, const SizedBox(height: _gap)),
      );

  static List<Widget> _spaced(List<Widget> children, Widget gap) => [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) gap, Expanded(child: children[i])],
      ];
}

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder();

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Colors.black87,
        child: Center(child: Icon(Icons.play_circle_outline, color: Colors.white, size: 48)),
      );
}
