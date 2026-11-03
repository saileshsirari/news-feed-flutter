import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_media/shared_media.dart';

/// Each upload waits until the test completes it, so in-between states can be checked.
class FakeUploadService implements MediaUploadService {
  final pending = <(PickedMedia, void Function(double)?, Completer<MediaAttachment>)>[];
  var _nextId = 100;

  @override
  Future<MediaAttachment> upload(PickedMedia media, {void Function(double progress)? onProgress}) {
    final completer = Completer<MediaAttachment>();
    pending.add((media, onProgress, completer));
    return completer.future;
  }

  void finish(int index) => pending[index].$3.complete(MediaAttachment(
        id: _nextId++,
        kind: MediaKind.image,
        url: Uri.parse('https://bucket.test/view'),
        contentType: 'image/jpeg',
        sizeBytes: 1,
      ));

  void fail(int index) => pending[index].$3.completeError(Exception('network down'));
}

PickedMedia image([int size = 10]) => PickedMedia(bytes: Uint8List(size), contentType: 'image/jpeg');

void main() {
  late FakeUploadService uploads;
  late ProviderContainer container;
  const feed = (id: 'feed', maxItems: 3);

  setUp(() {
    uploads = FakeUploadService();
    container = ProviderContainer.test(overrides: [mediaUploadServiceProvider.overrideWithValue(uploads)]);
  });

  (MediaDraftNotifier, ProviderSubscription<MediaDraftState>) open(MediaDraftKey key) {
    final sub = container.listen(mediaDraftProvider(key), (_, _) {});
    return (container.read(mediaDraftProvider(key).notifier), sub);
  }

  test('uploads each file as it is added, and gives ids only when all are ready', () async {
    final (draft, sub) = open(feed);
    draft.add(image());
    draft.add(image());

    expect(sub.read().items.map((i) => i.status), [DraftItemStatus.uploading, DraftItemStatus.uploading]);
    expect(sub.read().mediaIds, isNull);

    uploads.pending[0].$2!(0.5);
    expect(sub.read().items.first.progress, 0.5);

    uploads.finish(0);
    await pumpEventQueue();
    expect(sub.read().mediaIds, isNull);

    uploads.finish(1);
    await pumpEventQueue();
    expect(sub.read().mediaIds, [100, 101]);
  });

  test('sends ids in the order the user arranged the files', () async {
    final (draft, sub) = open(feed);
    for (var i = 0; i < 3; i++) {
      draft.add(image());
    }
    for (var i = 0; i < 3; i++) {
      uploads.finish(i);
    }
    await pumpEventQueue();

    draft.move(2, 0);
    expect(sub.read().mediaIds, [102, 100, 101]);
    draft.move(0, 2);
    expect(sub.read().mediaIds, [100, 101, 102]);
  });

  test('refuses more files than the feature allows', () {
    final (draft, sub) = open(feed);
    expect([for (var i = 0; i < 4; i++) draft.add(image())], [true, true, true, false]);
    expect(sub.read().items, hasLength(3));
    expect(sub.read().isFull, isTrue);
  });

  test('a failed upload blocks sending until retried', () async {
    final (draft, sub) = open(feed);
    draft.add(image());
    uploads.fail(0);
    await pumpEventQueue();

    final item = sub.read().items.single;
    expect(item.status, DraftItemStatus.failed);
    expect(item.error, contains('retry'));
    expect(sub.read().mediaIds, isNull);

    draft.retry(item.localId);
    expect(sub.read().items.single.status, DraftItemStatus.uploading);
    uploads.finish(1);
    await pumpEventQueue();
    expect(sub.read().mediaIds, [100]);
  });

  test('a file the rules reject fails at once, without uploading', () {
    final (draft, sub) = open(feed);
    draft.add(PickedMedia(bytes: Uint8List(5), contentType: 'image/gif'));

    expect(uploads.pending, isEmpty);
    expect(sub.read().items.single.status, DraftItemStatus.failed);
    expect(sub.read().items.single.error, contains('type'));
  });

  test('removing a file mid-upload ignores its result', () async {
    final (draft, sub) = open(feed);
    draft.add(image());
    draft.remove(sub.read().items.single.localId);
    uploads.finish(0);
    await pumpEventQueue();

    expect(sub.read().isEmpty, isTrue);
    expect(sub.read().mediaIds, isEmpty);
  });

  test('each composer has its own draft', () {
    final (feedDraft, feedSub) = open(feed);
    final (_, chatSub) = open((id: 'chat:42', maxItems: 10));
    feedDraft.add(image());

    expect(feedSub.read().items, hasLength(1));
    expect(chatSub.read().items, isEmpty);
    expect(chatSub.read().maxItems, 10);
  });

  test('clear empties the draft after sending', () async {
    final (draft, sub) = open(feed);
    draft.add(image());
    uploads.finish(0);
    await pumpEventQueue();
    draft.clear();
    expect(sub.read().isEmpty, isTrue);
  });
}
