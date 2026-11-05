import 'package:flutter/material.dart';

import '../models/media_attachment.dart';
import 'media_image.dart';
import 'media_viewer_screen.dart';
import 'video_player_screen.dart';
import 'video_tile.dart';

/// A post's or message's attachments, laid out like most social apps:
/// one file at its own shape, two side by side, three as one large and two
/// small, four or more as a 2×2 grid with "+N" on the last tile.
class MediaGrid extends StatelessWidget {
  const MediaGrid({
    super.key,
    required this.media,
    this.onTap,
    this.tileBuilder = defaultTile,
    this.viewerImageBuilder = MediaViewerScreen.defaultImage,
  });

  final List<MediaAttachment> media;

  /// Called with the tapped file's index in [media]. Left null, tapping a
  /// video plays it full screen, and tapping a photo (or the "+N" tile)
  /// opens all the files full screen at that one.
  final ValueChanged<int>? onTap;

  /// How one file is drawn; tests swap it to avoid network images.
  final Widget Function(MediaAttachment media) tileBuilder;

  /// How the full-screen viewer draws a photo; tests swap it too.
  final Widget Function(MediaAttachment media) viewerImageBuilder;

  static const _gap = 2.0;
  static const _maxTiles = 4;

  static Widget defaultTile(MediaAttachment media) => switch (media.kind) {
        MediaKind.image => MediaImage(media),
        MediaKind.video => VideoTile(media),
      };

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(aspectRatio: _aspectRatio(), child: _layout(context)),
    );
  }

  /// A single file keeps its own shape, within limits so a panorama or a
  /// tall screenshot doesn't take over the feed; several share a fixed box.
  double _aspectRatio() {
    if (media.length > 1) return 16 / 10;
    return (media.first.aspectRatio ?? 4 / 3).clamp(3 / 4, 1.91);
  }

  Widget _layout(BuildContext context) {
    Widget tile(int index, {int hiddenCount = 0}) => _tile(context, index, hiddenCount: hiddenCount);
    switch (media.length) {
      case 1:
        return tile(0);
      case 2:
        return _row([tile(0), tile(1)]);
      case 3:
        return _row([tile(0), _column([tile(1), tile(2)])]);
      default:
        return _column([
          _row([tile(0), tile(1)]),
          _row([tile(2), tile(3, hiddenCount: media.length - _maxTiles)]),
        ]);
    }
  }

  VoidCallback _onTapFor(BuildContext context, int index, {required bool coversHidden}) {
    if (onTap != null) return () => onTap!(index);
    // A video plays straight away; the "+N" tile (even over a video) opens
    // the viewer, which is where the hidden files are.
    if (media[index].kind == MediaKind.video && !coversHidden) {
      return () => VideoPlayerScreen.open(context, media[index]);
    }
    return () => MediaViewerScreen.open(context, media, initialIndex: index, imageBuilder: viewerImageBuilder);
  }

  Widget _tile(BuildContext context, int index, {int hiddenCount = 0}) {
    return GestureDetector(
      onTap: _onTapFor(context, index, coversHidden: hiddenCount > 0),
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
