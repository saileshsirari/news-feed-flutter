import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/media_attachment.dart';
import 'media_image.dart';
import 'video_player_screen.dart';
import 'video_tile.dart';

/// A post's or message's files full screen, starting at the tapped one:
/// pinch or double-tap to zoom a photo, swipe for the next file, × or Esc to
/// close. A video shows its poster here; tapping it plays it (in
/// [VideoPlayerScreen], as from the grid).
///
/// With a mouse a swipe isn't a drag (Flutter web and desktop don't drag
/// pages with the mouse), so there are ‹ › buttons and the arrow keys too.
class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({
    super.key,
    required this.media,
    this.initialIndex = 0,
    this.imageBuilder = defaultImage,
  });

  final List<MediaAttachment> media;
  final int initialIndex;

  /// How a photo is drawn; tests swap it to avoid network images.
  final Widget Function(MediaAttachment media) imageBuilder;

  static Widget defaultImage(MediaAttachment media) => MediaImage(media, fit: BoxFit.contain);

  static Future<void> open(
    BuildContext context,
    List<MediaAttachment> media, {
    int initialIndex = 0,
    Widget Function(MediaAttachment media) imageBuilder = defaultImage,
  }) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => MediaViewerScreen(media: media, initialIndex: initialIndex, imageBuilder: imageBuilder),
        ),
      );

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  /// While a photo is zoomed in, a drag pans the photo instead of turning
  /// the page.
  bool _zoomed = false;

  static final bool _usesMouse = kIsWeb ||
      const {TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux}.contains(defaultTargetPlatform);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final target = _index + delta;
    if (target < 0 || target >= widget.media.length) return;
    _pages.animateToPage(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.media.length;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pages,
                  physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
                  itemCount: count,
                  onPageChanged: (i) => setState(() {
                    _index = i;
                    _zoomed = false;
                  }),
                  itemBuilder: (context, i) => _page(context, widget.media[i]),
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
                if (count > 1)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Text('${_index + 1} / $count', style: const TextStyle(color: Colors.white70)),
                  ),
                if (count > 1 && _usesMouse) ...[
                  if (_index > 0) _arrow(Alignment.centerLeft, Icons.chevron_left, 'Previous', () => _go(-1)),
                  if (_index < count - 1) _arrow(Alignment.centerRight, Icons.chevron_right, 'Next', () => _go(1)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _page(BuildContext context, MediaAttachment media) => switch (media.kind) {
        MediaKind.image => _ZoomableImage(
            onZoomChanged: (zoomed) {
              if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
            },
            child: widget.imageBuilder(media),
          ),
        MediaKind.video => Center(
            child: AspectRatio(
              aspectRatio: media.aspectRatio ?? 16 / 9,
              child: GestureDetector(
                onTap: () => VideoPlayerScreen.open(context, media),
                child: VideoTile(media),
              ),
            ),
          ),
      };

  Widget _arrow(Alignment alignment, IconData icon, String tooltip, VoidCallback onPressed) => Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
            icon: Icon(icon, size: 32),
            tooltip: tooltip,
            onPressed: onPressed,
          ),
        ),
      );
}

/// A photo that zooms: pinch (or trackpad), or double-tap to toggle 2.5×
/// around the tapped point.
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({required this.child, required this.onZoomChanged});

  final Widget child;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final _transform = TransformationController();
  Offset _doubleTapAt = Offset.zero;

  static const _doubleTapScale = 2.5;

  bool get _isZoomed => _transform.value.getMaxScaleOnAxis() > 1.01;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (_isZoomed) {
      _transform.value = Matrix4.identity();
    } else {
      // Scale around the tapped point: move it to the origin, scale, move back.
      final p = _doubleTapAt;
      _transform.value = Matrix4.identity()
        ..translateByDouble(-p.dx * (_doubleTapScale - 1), -p.dy * (_doubleTapScale - 1), 0, 1)
        ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1);
    }
    widget.onZoomChanged(_isZoomed);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _transform,
        maxScale: 5,
        onInteractionEnd: (_) => widget.onZoomChanged(_isZoomed),
        child: SizedBox.expand(child: widget.child),
      ),
    );
  }
}
