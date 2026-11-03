import 'package:flutter/material.dart';
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

  testWidgets('the default tile shows a play icon for video until playback exists', (tester) async {
    await tester.pumpWidget(MaterialApp(home: MediaGrid(media: [attachment(1, kind: MediaKind.video)])));
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
  });
}
