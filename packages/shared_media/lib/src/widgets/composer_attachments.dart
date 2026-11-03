import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../draft/media_draft.dart';
import '../draft/media_draft_notifier.dart';
import '../models/media_attachment.dart';
import '../providers.dart';
import 'video_tile.dart';

/// The row of attached files in a composer: drag to reorder, × to remove,
/// a progress ring while uploading, tap a failed one to retry. Shows
/// nothing when the draft is empty.
class ComposerAttachments extends ConsumerWidget {
  const ComposerAttachments({super.key, required this.draftKey});

  final MediaDraftKey draftKey;

  static const tileSize = 88.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(mediaDraftProvider(draftKey));
    final notifier = ref.read(mediaDraftProvider(draftKey).notifier);
    if (draft.isEmpty) return const SizedBox.shrink();

    final firstError = draft.items.where((i) => i.status == DraftItemStatus.failed).firstOrNull?.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // A definite width as well as height: some hosts (AlertDialog does)
        // measure their content's natural width, which a scrolling list
        // can't report, and that failed the whole dialog's layout. This
        // takes the available width instead, so put it somewhere with a
        // bounded width (a Column in a dialog or screen, not a Row).
        SizedBox(
          width: double.maxFinite,
          height: tileSize,
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            buildDefaultDragHandles: false,
            itemCount: draft.items.length,
            // Gives the final index, which is what MediaDraftNotifier.move takes.
            onReorderItem: notifier.move,
            itemBuilder: (context, index) {
              final item = draft.items[index];
              return ReorderableDelayedDragStartListener(
                key: ValueKey(item.localId),
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _AttachmentTile(
                    item: item,
                    onRemove: () => notifier.remove(item.localId),
                    onRetry: () => notifier.retry(item.localId),
                  ),
                ),
              );
            },
          ),
        ),
        if (firstError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              firstError,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.item, required this.onRemove, required this.onRetry});

  final DraftItem item;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: ComposerAttachments.tileSize,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Preview(item),
            if (item.status == DraftItemStatus.uploading)
              ColoredBox(
                color: Colors.black38,
                child: Center(
                  child: CircularProgressIndicator(
                    // Indeterminate until the first bytes go out.
                    value: item.progress > 0 ? item.progress : null,
                    color: Colors.white,
                  ),
                ),
              ),
            if (item.status == DraftItemStatus.failed)
              Material(
                color: colors.error.withValues(alpha: 0.6),
                child: InkWell(
                  onTap: onRetry,
                  child: Tooltip(
                    message: item.error ?? 'Upload failed',
                    child: Icon(Icons.refresh, color: colors.onError),
                  ),
                ),
              ),
            Positioned(
              top: 2,
              right: 2,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onRemove,
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close, size: 16, color: Colors.white, semanticLabel: 'Remove'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The picked file itself: the photo, or a video's poster (made on the
/// device) with its length.
class _Preview extends StatelessWidget {
  const _Preview(this.item);

  final DraftItem item;

  @override
  Widget build(BuildContext context) {
    final source = item.source;
    if (source.kind == MediaKind.image) return Image.memory(source.bytes, fit: BoxFit.cover, gaplessPlayback: true);
    final poster = source.thumbnail;
    return Stack(
      fit: StackFit.expand,
      children: [
        poster != null
            ? Image.memory(poster, fit: BoxFit.cover, gaplessPlayback: true)
            : const ColoredBox(color: Colors.black87, child: Icon(Icons.videocam, color: Colors.white)),
        if (source.durationMs != null)
          Positioned(left: 4, bottom: 4, child: DurationBadge(milliseconds: source.durationMs!)),
      ],
    );
  }
}

/// Opens the gallery for photos and videos and adds what's picked to the
/// draft, up to the draft's limit. Disabled once the draft is full.
class AddMediaButton extends ConsumerWidget {
  const AddMediaButton({super.key, required this.draftKey});

  final MediaDraftKey draftKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(mediaDraftProvider(draftKey));
    return IconButton(
      tooltip: draft.isFull ? 'At most ${draft.maxItems} files' : 'Add photos or videos',
      icon: const Icon(Icons.add_photo_alternate_outlined),
      onPressed: draft.isFull
          ? null
          : () async {
              final notifier = ref.read(mediaDraftProvider(draftKey).notifier);
              final picked = await ref.read(mediaPickerProvider).pickMedia(limit: draft.maxItems - draft.items.length);
              picked.forEach(notifier.add);
            },
    );
  }
}
