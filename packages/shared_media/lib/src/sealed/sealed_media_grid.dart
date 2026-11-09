import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/media_upload_service.dart';
import '../models/media_attachment.dart';
import '../models/sealed_attachment.dart';
import '../widgets/media_grid.dart';
import '../widgets/media_viewer_screen.dart';
import '../widgets/video_player_screen.dart';
import '../widgets/video_tile.dart';
import 'media_sealer.dart';

/// Where an encrypted file can be downloaded now (the server's links
/// expire, so it's asked when needed), or null if it's gone.
typedef SealedLinkOf = Future<Uri?> Function(int mediaId);

/// One encrypted file to open, and where to get it. Equal by the file, so
/// every bubble showing it shares one download.
class SealedMediaRequest {
  const SealedMediaRequest(this.attachment, this.linkOf);

  final SealedAttachment attachment;
  final SealedLinkOf linkOf;

  @override
  bool operator ==(Object other) => other is SealedMediaRequest && other.attachment == attachment;

  @override
  int get hashCode => attachment.hashCode;
}

/// Downloads encrypted files; overridable for tests.
final sealedDownloadClientProvider = Provider<http.Client>((ref) => http.Client());

/// An encrypted file, opened: from this device if it was opened before (or
/// sent from here), otherwise downloaded and decrypted, then kept.
final openedMediaProvider = FutureProvider.family<MediaAttachment, SealedMediaRequest>((ref, request) async {
  final attachment = request.attachment;
  final kept = await findOpened(attachment);
  if (kept != null) return kept;
  final link = await request.linkOf(attachment.mediaId);
  if (link == null) throw StateError('this file is no longer on the server');
  final response = await ref.read(sealedDownloadClientProvider).get(link);
  if (response.statusCode != 200) throw StateError('download failed (${response.statusCode})');
  final bytes = await ref.read(mediaSealerProvider).open(attachment.key, response.bodyBytes);
  return keepOpened(attachment, bytes);
});

/// An encrypted message's photos and videos: each shows its tiny preview
/// while it downloads and decrypts, then itself, laid out like [MediaGrid].
class SealedMediaGrid extends ConsumerWidget {
  const SealedMediaGrid({super.key, required this.media, required this.linkOf});

  final List<SealedAttachment> media;
  final SealedLinkOf linkOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = [for (final m in media) SealedMediaRequest(m, linkOf)];
    final opened = [for (final r in requests) ref.watch(openedMediaProvider(r))];
    // Not opened yet: a stand-in with the right shape, drawn by _Pending.
    final shown = [for (var i = 0; i < media.length; i++) opened[i].value ?? media[i].opened(Uri())];
    return MediaGrid(
      media: shown,
      tileBuilder: (tile) {
        final i = shown.indexWhere((m) => m.id == tile.id);
        return opened[i].hasValue ? MediaGrid.defaultTile(tile) : _Pending(media[i], failed: opened[i].hasError);
      },
      onTap: (index) {
        if (opened[index].hasError) return ref.invalidate(openedMediaProvider(requests[index])); // try again
        if (!opened[index].hasValue) return;
        if (shown[index].kind == MediaKind.video) {
          VideoPlayerScreen.open(context, shown[index]);
          return;
        }
        final ready = [
          for (var i = 0; i < shown.length; i++)
            if (opened[i].hasValue) shown[i],
        ];
        MediaViewerScreen.open(context, ready, initialIndex: ready.indexWhere((m) => m.id == shown[index].id));
      },
    );
  }
}

/// A file still downloading (or failed): its blurred preview, if it came
/// with one, and a spinner (or a retry sign).
class _Pending extends StatelessWidget {
  const _Pending(this.media, {required this.failed});

  final SealedAttachment media;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final preview = media.preview;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: colors.surfaceContainerHighest),
        if (preview != null)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Image.memory(preview, fit: BoxFit.cover, gaplessPlayback: true),
          ),
        Center(
          child: failed
              ? const DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.refresh, color: Colors.white, semanticLabel: 'Couldn\'t load. Tap to retry'),
                  ),
                )
              : const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3)),
        ),
        if (media.kind == MediaKind.video && media.durationMs != null)
          Positioned(right: 6, bottom: 6, child: DurationBadge(milliseconds: media.durationMs!)),
      ],
    );
  }
}
