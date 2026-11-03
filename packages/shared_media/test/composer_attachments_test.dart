import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_media/shared_media.dart';

/// A real 1×1 PNG, so Image.memory can decode the preview.
final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

PickedMedia pngMedia() => PickedMedia(bytes: png, contentType: 'image/png', width: 1, height: 1);

class FakeUploadService implements MediaUploadService {
  final pending = <Completer<MediaAttachment>>[];

  @override
  Future<MediaAttachment> upload(PickedMedia media, {void Function(double progress)? onProgress}) {
    final completer = Completer<MediaAttachment>();
    pending.add(completer);
    return completer.future;
  }
}

class FakePicker implements MediaPicker {
  int? lastLimit;

  @override
  Future<List<PickedMedia>> pickImages({required int limit}) async {
    lastLimit = limit;
    return [pngMedia(), pngMedia()];
  }
}

void main() {
  const key = (id: 'test', maxItems: 3);
  late FakeUploadService uploads;
  late FakePicker picker;
  late ProviderContainer container;

  setUp(() {
    uploads = FakeUploadService();
    picker = FakePicker();
    container = ProviderContainer.test(overrides: [
      mediaUploadServiceProvider.overrideWithValue(uploads),
      mediaPickerProvider.overrideWithValue(picker),
    ]);
    // The draft is autoDispose; a composer screen keeps it alive by
    // watching it, and so does this listener while a test sets it up.
    container.listen(mediaDraftProvider(key), (_, _) {});
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: Column(children: [AddImagesButton(draftKey: key), ComposerAttachments(draftKey: key)]),
          ),
        ),
      ));

  MediaDraftState draft() => container.read(mediaDraftProvider(key));

  testWidgets('adds picked images, asking only for what still fits', (tester) async {
    await pump(tester);
    expect(find.byType(Image), findsNothing);

    await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
    await tester.pump();

    expect(picker.lastLimit, 3);
    expect(find.byType(Image), findsNWidgets(2));
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
    await tester.pump();
    expect(picker.lastLimit, 1);
    expect(draft().items, hasLength(3)); // the second pick offered 2, only 1 fit
  });

  testWidgets('the add button is disabled once the draft is full', (tester) async {
    for (var i = 0; i < 3; i++) {
      container.read(mediaDraftProvider(key).notifier).add(pngMedia());
    }
    await pump(tester);
    final button = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add_photo_alternate_outlined));
    expect(button.onPressed, isNull);
  });

  testWidgets('× removes a file', (tester) async {
    container.read(mediaDraftProvider(key).notifier).add(pngMedia());
    await pump(tester);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(draft().isEmpty, isTrue);
  });

  testWidgets('a failed upload shows its reason and retries on tap', (tester) async {
    container.read(mediaDraftProvider(key).notifier).add(pngMedia());
    await pump(tester);

    uploads.pending.single.completeError(Exception('offline'));
    await tester.pump();
    expect(find.text('Upload failed. Tap to retry.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(uploads.pending, hasLength(2));
    expect(draft().items.single.status, DraftItemStatus.uploading);
  });

  testWidgets('lays out inside an AlertDialog, which measures its content\'s natural width', (tester) async {
    container.read(mediaDraftProvider(key).notifier).add(pngMedia());
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: AlertDialog(
            title: Text('New post'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(), ComposerAttachments(draftKey: key)]),
            actions: [AddImagesButton(draftKey: key)],
          ),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsOneWidget);
  });
}
