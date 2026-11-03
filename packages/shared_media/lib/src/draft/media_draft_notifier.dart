import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/media_limits.dart';
import '../models/picked_media.dart';
import '../providers.dart';
import 'media_draft.dart';

/// The files attached in one composer: uploads each as soon as it's
/// picked, so it's usually ready by the time the user taps send. Used the
/// same way by the feed and chat composers; they only differ in their key.
class MediaDraftNotifier extends Notifier<MediaDraftState> {
  MediaDraftNotifier(this.draftKey);

  /// The family argument: `mediaDraftProvider((id: 'chat:42', maxItems: 10))`.
  final MediaDraftKey draftKey;
  int _nextLocalId = 0;

  @override
  MediaDraftState build() => MediaDraftState(items: const [], maxItems: draftKey.maxItems);

  /// Adds [media] at the end and starts uploading it. Returns false (and
  /// adds nothing) if the draft is already full. A file the rules reject is
  /// added as failed, with the reason, so the user sees why.
  bool add(PickedMedia media) {
    if (state.isFull) return false;
    final problem = MediaLimits.problemWith(media);
    final item = DraftItem(
      localId: _nextLocalId++,
      source: media,
      status: problem == null ? DraftItemStatus.uploading : DraftItemStatus.failed,
      error: problem,
    );
    state = state.copyWith(items: [...state.items, item]);
    if (problem == null) _upload(item.localId);
    return true;
  }

  /// A file already uploaded but never sent is left for the server's
  /// cleanup of unclaimed uploads; nothing to undo here.
  void remove(int localId) {
    state = state.copyWith(items: [for (final i in state.items) if (i.localId != localId) i]);
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
    _replace(item.copyWith(status: DraftItemStatus.uploading, progress: 0));
    _upload(localId);
  }

  /// After the post or message was sent with [MediaDraftState.mediaIds].
  void clear() => state = state.copyWith(items: const []);

  Future<void> _upload(int localId) async {
    final source = _find(localId)!.source;
    try {
      final uploaded = await ref.read(mediaUploadServiceProvider).upload(
            source,
            onProgress: (p) => _update(localId, (i) => i.copyWith(progress: p)),
          );
      _update(localId, (i) => i.copyWith(status: DraftItemStatus.ready, progress: 1, uploaded: uploaded));
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
final mediaDraftProvider =
    NotifierProvider.autoDispose.family<MediaDraftNotifier, MediaDraftState, MediaDraftKey>(MediaDraftNotifier.new);
