import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_kit/geo_kit.dart';

/// Answers from a list; records what it was asked.
class FakeSearch implements PlaceSearch {
  final searches = <String>[];
  final reverses = <GeoPoint>[];
  Place? reverseAnswer = const Place(
    name: '100 Feet Road',
    address: '12, 100 Feet Road, Indiranagar, Bengaluru, Karnataka, 560038, India',
    point: GeoPoint(12.97194, 77.64123),
  );

  @override
  Future<List<Place>> search(String query, {GeoPoint? near}) async {
    searches.add(query);
    return [const Place(name: 'Cubbon Park', address: 'Cubbon Park, Bengaluru', point: GeoPoint(12.9763, 77.5929))];
  }

  @override
  Future<Place?> reverse(GeoPoint point) async {
    reverses.add(point);
    return reverseAnswer;
  }
}

class FakeLocation implements LocationSource {
  FakeLocation(this.answer);
  final Object answer;

  @override
  Future<GeoPoint> current() async => switch (answer) {
        final GeoPoint p => p,
        final LocationUnavailable e => throw e,
        _ => throw StateError('bad fake'),
      };
}

void main() {
  /// Pumps a button that opens the picker; [result] gets what it returned.
  Future<void> open(WidgetTester tester, FakeSearch search, ValueChanged<Place?> result,
      {bool areaOnly = false, LocationSource? location}) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result(await pickPlace(context,
              search: search, tiles: MapTiles.none, areaOnly: areaOnly, location: location)),
          child: const Text('pick'),
        ),
      ),
    ));
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
  }

  testWidgets('search only when asked, then choose a result', (tester) async {
    final search = FakeSearch();
    Place? picked;
    await open(tester, search, (p) => picked = p);

    await tester.enterText(find.byType(TextField), 'cubbon');
    await tester.pump();
    expect(search.searches, isEmpty, reason: 'typing alone must not search');

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(search.searches, ['cubbon']);

    await tester.tap(find.text('Cubbon Park').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use Cubbon Park'));
    await tester.pumpAndSettle();

    expect(picked!.name, 'Cubbon Park');
    expect(picked!.point, const GeoPoint(12.9763, 77.5929));
    expect(search.reverses, isEmpty, reason: 'a searched place already has its name');
  });

  testWidgets('an area is rounded to about a kilometre and named by neighbourhood', (tester) async {
    final search = FakeSearch();
    Place? picked;
    await open(tester, search, (p) => picked = p,
        areaOnly: true, location: FakeLocation(const GeoPoint(12.97194, 77.64123)));

    await tester.tap(find.byTooltip('My location'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this area'));
    await tester.pumpAndSettle();

    expect(search.reverses, [const GeoPoint(12.97, 77.64)], reason: 'only the rounded point leaves the phone');
    expect(picked!.point, const GeoPoint(12.97, 77.64));
    expect(picked!.name, 'Indiranagar, Bengaluru');
    expect(picked!.address, isNull);
  });

  testWidgets('says why when location is off', (tester) async {
    await open(tester, FakeSearch(), (_) {},
        location: FakeLocation(const LocationUnavailable('Location is switched off on this device.')));
    await tester.tap(find.byTooltip('My location'));
    await tester.pumpAndSettle();
    expect(find.text('Location is switched off on this device.'), findsOneWidget);
  });
}
