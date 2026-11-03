import '../models/media_attachment.dart';
import '../models/picked_media.dart';

/// Which composer a draft belongs to, and how many files that feature
/// allows: e.g. `(id: 'feed', maxItems: 10)` or `(id: 'chat:42', maxItems: 10)`.
/// A record, so two equal keys find the same draft.
typedef MediaDraftKey = ({String id, int maxItems});

enum DraftItemStatus { uploading, ready, failed }

/// One picked file in a composer, from upload start to ready (or failed).
class DraftItem {
  const DraftItem({
    required this.localId,
    required this.source,
    required this.status,
    this.progress = 0,
    this.uploaded,
    this.error,
  });

  /// Stable while the item exists, for widget keys and remove/retry.
  final int localId;

  /// Kept for the preview and for retrying.
  final PickedMedia source;
  final DraftItemStatus status;

  /// 0..1 while uploading.
  final double progress;
  final MediaAttachment? uploaded;
  final String? error;

  DraftItem copyWith({DraftItemStatus? status, double? progress, MediaAttachment? uploaded, String? error}) => DraftItem(
        localId: localId,
        source: source,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        uploaded: uploaded ?? this.uploaded,
        error: error,
      );
}

class MediaDraftState {
  const MediaDraftState({required this.items, required this.maxItems});

  /// In the order the user arranged them, which is the order they're sent in.
  final List<DraftItem> items;
  final int maxItems;

  bool get isEmpty => items.isEmpty;
  bool get isFull => items.length >= maxItems;
  bool get isUploading => items.any((i) => i.status == DraftItemStatus.uploading);
  bool get hasFailures => items.any((i) => i.status == DraftItemStatus.failed);

  /// The ids to send with the post or message, in order — or null while
  /// anything is still uploading or has failed, since sending then would
  /// silently drop those files.
  List<int>? get mediaIds =>
      items.every((i) => i.status == DraftItemStatus.ready) ? [for (final i in items) i.uploaded!.id] : null;

  MediaDraftState copyWith({List<DraftItem>? items}) => MediaDraftState(items: items ?? this.items, maxItems: maxItems);
}
