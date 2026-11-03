import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_media/shared_media.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePicker implements MediaPicker {
  FakePicker(this.result);

  final List<PickedMedia> result;

  @override
  Future<List<PickedMedia>> pickMedia({required int limit}) async => result;
}

class NeverUploads implements MediaUploadService {
  @override
  Future<MediaAttachment> upload(PickedMedia media, {void Function(double progress)? onProgress}) =>
      Completer<MediaAttachment>().future;
}

class NeverPrepares implements VideoPreparer {
  @override
  Future<PickedMedia> prepare(PickedMedia media, {required VideoUploadQuality quality, void Function(double)? onProgress}) =>
      Completer<PickedMedia>().future;
}

final phoneVideo =
    PickedMedia.notLoaded(sourcePath: '/v.mp4', contentType: 'video/mp4', sizeBytes: 20 * 1024 * 1024, durationMs: 10000);
final photo = PickedMedia(bytes: Uint8List(10), contentType: 'image/jpeg');

void main() {
  const key = (id: 'test', maxItems: 10);

  Future<ProviderContainer> pump(WidgetTester tester, List<PickedMedia> picks, {Map<String, Object> saved = const {}}) async {
    SharedPreferences.setMockInitialValues(saved);
    final container = ProviderContainer.test(overrides: [
      mediaPickerProvider.overrideWithValue(FakePicker(picks)),
      mediaUploadServiceProvider.overrideWithValue(NeverUploads()),
      videoPreparerProvider.overrideWithValue(NeverPrepares()),
    ]);
    container.listen(mediaDraftProvider(key), (_, _) {});
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: Center(child: AddMediaButton(draftKey: key)))),
    ));
    return container;
  }

  Future<void> tapAdd(WidgetTester tester) async {
    await tester.tap(find.byType(AddMediaButton));
    await tester.pumpAndSettle();
  }

  testWidgets('the first video asks for a quality, then adds it with that choice saved', (tester) async {
    final container = await pump(tester, [phoneVideo]);
    await tapAdd(tester);

    expect(find.text('Video upload quality'), findsOneWidget);
    expect(find.text('You can change this any time in Settings.'), findsOneWidget);
    expect(find.text('540p (recommended)'), findsOneWidget);

    await tester.ensureVisible(find.text('480p'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('480p'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(container.read(mediaSettingsProvider).value!.videoQuality, VideoUploadQuality.p480);
    expect(container.read(mediaDraftProvider(key)).items, hasLength(1));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('shared_media.videoUploadQuality'), 'p480');
  });

  testWidgets('doesn\'t ask again once a quality has been chosen', (tester) async {
    await pump(tester, [phoneVideo], saved: {'shared_media.videoUploadQuality': 'p720'});
    await tapAdd(tester);
    expect(find.text('Video upload quality'), findsNothing);
  });

  testWidgets('doesn\'t ask for photos', (tester) async {
    await pump(tester, [photo]);
    await tapAdd(tester);
    expect(find.text('Video upload quality'), findsNothing);
  });

  testWidgets('dismissing it keeps the default and still adds the video', (tester) async {
    final container = await pump(tester, [phoneVideo]);
    await tapAdd(tester);
    await tester.tapAt(const Offset(10, 10)); // outside the sheet
    await tester.pumpAndSettle();

    expect(container.read(mediaDraftProvider(key)).items, hasLength(1));
    expect(container.read(mediaSettingsProvider).value!.hasChosenVideoQuality, isFalse);
  });

  test('estimates: smaller qualities are smaller and faster, and Original warns about the limit', () {
    final sizes = [for (final q in VideoUploadQuality.values) q.approxMegabytes(30)];
    expect(sizes, orderedEquals([...sizes]..sort((a, b) => b.compareTo(a))));
    expect(VideoUploadQuality.p540.approxMegabytes(30).round(), 9);
    expect(VideoUploadQuality.p540.approxUploadSeconds(30), 15);
    expect(VideoUploadQuality.original.approxMegabytes(30), greaterThan(50));
  });
}
