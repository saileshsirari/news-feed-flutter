import '../models/media_attachment.dart';
import '../models/picked_media.dart';
import '../models/sealed_attachment.dart';

/// Which composer a draft belongs to, how many files that feature allows,
/// and whether its files are encrypted before upload (an end-to-end
/// encrypted chat): e.g. `(id: 'feed', maxItems: 10, sealed: false)`.
/// A record, so two equal keys find the same draft.
typedef MediaDraftKey = ({String id, int maxItems, bool sealed});

enum DraftItemStatus {
  /// Being compressed on the device (phone videos), before uploading.
  preparing,
  uploading,
  ready,
  failed,
}

/// One picked file in a composer, from upload start to ready (or failed).
class DraftItem {
  const DraftItem({
    required this.localId,
    required this.source,
    required this.status,
    this.progress = 0,
    this.uploaded,
    this.sealed,
    this.error,
  });

  /// Stable while the item exists, for widget keys and remove/retry.
  final int localId;

  /// Kept for the preview and for retrying.
  final PickedMedia source;
  final DraftItemStatus status;

  /// 0..1 while preparing, and again while uploading.
  final double progress;
  final MediaAttachment? uploaded;

  /// Instead of [uploaded], in a draft whose files are encrypted.
  final SealedAttachment? sealed;
  final String? error;

  DraftItem copyWith({
    PickedMedia? source,
    DraftItemStatus? status,
    double? progress,
    MediaAttachment? uploaded,
    SealedAttachment? sealed,
    String? error,
  }) => DraftItem(
    localId: localId,
    source: source ?? this.source,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    uploaded: uploaded ?? this.uploaded,
    sealed: sealed ?? this.sealed,
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
  bool get isPreparing => items.any((i) => i.status == DraftItemStatus.preparing);
  bool get isUploading => items.any((i) => i.status == DraftItemStatus.uploading);
  bool get hasFailures => items.any((i) => i.status == DraftItemStatus.failed);

  /// The ids to send with the post or message, in order — or null while
  /// anything is still being prepared, uploading, or has failed, since
  /// sending then would silently drop those files.
  List<int>? get mediaIds => _allReady ? [for (final i in items) i.uploaded?.id ?? i.sealed!.mediaId] : null;

  /// For an encrypted draft: what each file is and its key, for the
  /// encrypted message; null like [mediaIds] until every file is ready.
  List<SealedAttachment>? get sealedAttachments => _allReady ? [for (final i in items) i.sealed!] : null;

  bool get _allReady => items.every((i) => i.status == DraftItemStatus.ready);

  MediaDraftState copyWith({List<DraftItem>? items}) => MediaDraftState(items: items ?? this.items, maxItems: maxItems);
}
