import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/media_limits.dart';
import '../models/picked_media.dart';
import '../providers.dart';
import '../sealed/media_sealer.dart';
import '../settings/media_settings.dart';
import 'media_draft.dart';

/// The files attached in one composer: prepares (compresses) and uploads
/// each as soon as it's picked, so it's usually ready by the time the user
/// taps send. Used the same way by the feed and chat composers; they only
/// differ in their key.
class MediaDraftNotifier extends Notifier<MediaDraftState> {
  MediaDraftNotifier(this.draftKey);

  /// The family argument: `mediaDraftProvider((id: 'chat:42', maxItems: 10, sealed: false))`.
  final MediaDraftKey draftKey;
  int _nextLocalId = 0;

  @override
  MediaDraftState build() => MediaDraftState(items: const [], maxItems: draftKey.maxItems);

  /// Adds [media] at the end and starts preparing and uploading it. Returns
  /// false (and adds nothing) if the draft is already full. A file the
  /// rules reject is added as failed, with the reason, so the user sees why
  /// before any time is spent compressing or uploading it.
  bool add(PickedMedia media) {
    if (state.isFull) return false;
    final problem = MediaLimits.problemWith(media);
    final item = DraftItem(
      localId: _nextLocalId++,
      source: media,
      status: problem != null
          ? DraftItemStatus.failed
          : media.needsPreparing
          ? DraftItemStatus.preparing
          : DraftItemStatus.uploading,
      error: problem,
    );
    state = state.copyWith(items: [...state.items, item]);
    if (problem == null) _process(item.localId);
    return true;
  }

  /// A file already uploaded but never sent is left for the server's
  /// cleanup of unclaimed uploads; nothing to undo here.
  void remove(int localId) {
    state = state.copyWith(
      items: [
        for (final i in state.items)
          if (i.localId != localId) i,
      ],
    );
  }

  /// Moves the item at [from] so it ends up at index [to] (both in the
  /// current list), the indices ReorderableListView's onReorderItem gives.
  void move(int from, int to) {
    final items = [...state.items];
    items.insert(to, items.removeAt(from));
    state = state.copyWith(items: items);
  }

  void retry(int localId) {
    final item = _find(localId);
    if (item == null || item.status != DraftItemStatus.failed) return;
    if (MediaLimits.problemWith(item.source) != null) return; // retrying can't fix a rule violation
    final status = item.source.needsPreparing ? DraftItemStatus.preparing : DraftItemStatus.uploading;
    _replace(item.copyWith(status: status, progress: 0));
    _process(localId);
  }

  /// After the post or message was sent with [MediaDraftState.mediaIds].
  void clear() => state = state.copyWith(items: const []);

  Future<void> _process(int localId) async {
    var source = _find(localId)!.source;
    if (source.needsPreparing) {
      final settings = await ref.read(mediaSettingsProvider.future);
      final quality = settings.videoQuality;
      // Uncompressed, the original itself has to fit the server's limit:
      // say so now, before reading the whole file.
      if (!quality.compresses && source.sizeBytes > MediaLimits.maxVideoBytes) {
        final problem = MediaLimits.originalTooLarge(source.sizeBytes);
        _update(localId, (i) => i.copyWith(status: DraftItemStatus.failed, error: problem));
        return;
      }
      try {
        source = await ref
            .read(videoPreparerProvider)
            .prepare(
              source,
              quality: quality,
              onProgress: (p) => _update(localId, (i) => i.copyWith(progress: p)),
            );
      } catch (_) {
        _update(
          localId,
          (i) => i.copyWith(status: DraftItemStatus.failed, error: 'Couldn\'t read this video. Tap to retry.'),
        );
        return;
      }
      // Keep the prepared file, so a failed upload's retry doesn't compress again.
      final prepared = source;
      final problem = MediaLimits.problemWith(prepared);
      _update(
        localId,
        (i) => problem == null
            ? i.copyWith(source: prepared, status: DraftItemStatus.uploading, progress: 0)
            : i.copyWith(source: prepared, status: DraftItemStatus.failed, error: problem),
      );
      if (problem != null || _find(localId) == null) return;
    }
    await _upload(localId, source);
  }

  Future<void> _upload(int localId, PickedMedia source) async {
    try {
      void progress(double p) => _update(localId, (i) => i.copyWith(progress: p));
      final service = ref.read(mediaUploadServiceProvider);
      if (draftKey.sealed) {
        final sealed = await service.uploadSealed(source, ref.read(mediaSealerProvider), onProgress: progress);
        _update(localId, (i) => i.copyWith(status: DraftItemStatus.ready, progress: 1, sealed: sealed));
      } else {
        final uploaded = await service.upload(source, onProgress: progress);
        _update(localId, (i) => i.copyWith(status: DraftItemStatus.ready, progress: 1, uploaded: uploaded));
      }
    } catch (e) {
      _update(localId, (i) => i.copyWith(status: DraftItemStatus.failed, error: 'Upload failed. Tap to retry.'));
    }
  }

  /// Applies [change] to the item if it's still there: the user may have
  /// removed it, or closed the composer, while it was uploading.
  void _update(int localId, DraftItem Function(DraftItem) change) {
    if (!ref.mounted) return;
    final item = _find(localId);
    if (item != null) _replace(change(item));
  }

  DraftItem? _find(int localId) {
    for (final i in state.items) {
      if (i.localId == localId) return i;
    }
    return null;
  }

  void _replace(DraftItem item) {
    state = state.copyWith(items: [for (final i in state.items) i.localId == item.localId ? item : i]);
  }
}

/// autoDispose: a composer's attachments go away when the composer does.
final mediaDraftProvider = NotifierProvider.autoDispose.family<MediaDraftNotifier, MediaDraftState, MediaDraftKey>(
  MediaDraftNotifier.new,
);
