import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_media/shared_media.dart';

MediaAttachment attachment(int id, {MediaKind kind = MediaKind.image, int? width, int? height}) => MediaAttachment(
      id: id,
      kind: kind,
      url: Uri.parse('https://bucket.test/$id'),
      contentType: kind == MediaKind.image ? 'image/jpeg' : 'video/mp4',
      sizeBytes: 1,
      width: width,
      height: height,
    );

void main() {
  /// Draws each tile as a labelled box, so no network images are loaded.
  Future<void> pumpGrid(WidgetTester tester, List<MediaAttachment> media, {ValueChanged<int>? onTap}) =>
      tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 320,
            child: MediaGrid(
              media: media,
              onTap: onTap,
              tileBuilder: (m) => ColoredBox(color: Colors.grey, child: Text('tile ${m.id}')),
              viewerImageBuilder: (m) => Text('full ${m.id}'),
            ),
          ),
        ),
      ));

  testWidgets('shows nothing for no media', (tester) async {
    await pumpGrid(tester, []);
    expect(find.byType(AspectRatio), findsNothing);
  });

  testWidgets('a single image keeps its shape, within limits', (tester) async {
    await pumpGrid(tester, [attachment(1, width: 1600, height: 900)]);
    expect(tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio, closeTo(16 / 9, 0.001));

    await pumpGrid(tester, [attachment(1, width: 400, height: 4000)]); // a very tall screenshot
    expect(tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio, 3 / 4);
  });

  testWidgets('shows up to four tiles in order, with +N for the rest', (tester) async {
    await pumpGrid(tester, [for (var i = 1; i <= 6; i++) attachment(i)]);

    expect(find.textContaining('tile '), findsNWidgets(4));
    for (var i = 1; i <= 4; i++) {
      expect(find.text('tile $i'), findsOneWidget);
    }
    expect(find.text('+2'), findsOneWidget);
  });

  testWidgets('three files: one large on the left, two stacked on the right', (tester) async {
    await pumpGrid(tester, [attachment(1), attachment(2), attachment(3)]);

    final first = tester.getRect(find.text('tile 1'));
    final second = tester.getRect(find.text('tile 2'));
    final third = tester.getRect(find.text('tile 3'));
    expect(second.left, greaterThan(first.left));
    expect(third.top, greaterThan(second.top));
    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets('reports which tile was tapped', (tester) async {
    final taps = <int>[];
    await pumpGrid(tester, [attachment(1), attachment(2)], onTap: taps.add);
    await tester.tap(find.text('tile 2'));
    expect(taps, [1]);
  });

  testWidgets('a video tile shows a play button and its length', (tester) async {
    final video = MediaAttachment(
      id: 1,
      kind: MediaKind.video,
      url: Uri.parse('https://bucket.test/1.mp4'),
      contentType: 'video/mp4',
      sizeBytes: 1,
      durationMs: 75400,
    );
    await tester.pumpWidget(MaterialApp(home: MediaGrid(media: [video])));
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('1:15'), findsOneWidget);
  });

  group('full-screen viewer', () {
    testWidgets('tapping a photo opens it full screen, and × closes it', (tester) async {
      await pumpGrid(tester, [attachment(1), attachment(2)]);
      await tester.tap(find.text('tile 2'));
      await tester.pumpAndSettle();

      expect(find.byType(MediaViewerScreen), findsOneWidget);
      expect(find.text('full 2'), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(MediaViewerScreen), findsNothing);
    });

    testWidgets('swipes to the next file, and Esc closes', (tester) async {
      await pumpGrid(tester, [attachment(1), attachment(2), attachment(3)]);
      await tester.tap(find.text('tile 1'));
      await tester.pumpAndSettle();

      await tester.fling(find.text('full 1'), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('full 2'), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(MediaViewerScreen), findsNothing);
    });

    testWidgets('the arrow keys move between files', (tester) async {
      await pumpGrid(tester, [attachment(1), attachment(2)]);
      await tester.tap(find.text('tile 1'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
    });

    testWidgets('double-tap zooms a photo, and swiping then pans instead of turning the page', (tester) async {
      await pumpGrid(tester, [attachment(1), attachment(2)]);
      await tester.tap(find.text('tile 1'));
      await tester.pumpAndSettle();

      final photo = find.text('full 1');
      await tester.tap(photo);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(photo);
      await tester.pumpAndSettle();
      final zoom = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer).first);
      expect(zoom.transformationController!.value.getMaxScaleOnAxis(), greaterThan(2));

      await tester.fling(photo, const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
    });

    testWidgets('the +N tile opens the viewer there, to see the hidden files', (tester) async {
      await pumpGrid(tester, [for (var i = 1; i <= 6; i++) attachment(i)]);
      await tester.tap(find.text('+2'));
      await tester.pumpAndSettle();
      expect(find.text('4 / 6'), findsOneWidget);
    });
  });

  test('formats video lengths as m:ss', () {
    expect(formatVideoDuration(0), '0:00');
    expect(formatVideoDuration(7400), '0:07');
    expect(formatVideoDuration(30000), '0:30');
    expect(formatVideoDuration(90500), '1:31');
  });
}
