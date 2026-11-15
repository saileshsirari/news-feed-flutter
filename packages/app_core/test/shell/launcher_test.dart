import 'dart:convert';

import 'package:app_core/app_core.dart';
import 'package:app_core/config/app_config.dart';
import 'package:app_core/data/services/api_service.dart';
import 'package:app_core/data/services/service_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A mini-app with a plain home screen and one linkable screen.
class _FakeMiniApp extends MiniApp {
  _FakeMiniApp(String id, {bool isGlobal = false})
    : info = MiniAppInfo(id: id, name: _name(id), icon: Icons.apps, color: Colors.teal, isGlobal: isGlobal);

  static String _name(String id) => id[0].toUpperCase() + id.substring(1);

  @override
  final MiniAppInfo info;

  @override
  Widget buildHome(BuildContext context) => Scaffold(appBar: AppBar(title: Text('${info.name} home')));

  @override
  Widget? screenFor(Uri link) => AppLinks.idOf(link, 'thing') == null
      ? null
      : Scaffold(appBar: AppBar(), body: Text('${info.name} thing ${link.pathSegments[1]}'));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// The Home grid with [slots] compiled in, the server answering
  /// GET /config/apps with [server] (or failing when null).
  Future<void> pumpHome(WidgetTester tester, List<MiniAppSlot> slots, {Map<String, dynamic>? server}) async {
    final api = ApiService(
      AppConfig(apiBaseUrl: Uri.parse('https://example.test')),
      httpClient: MockClient((request) async {
        if (request.url.path != '/config/apps' || server == null) return http.Response('{}', 503);
        return http.Response(jsonEncode(server), 200);
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiServiceProvider.overrideWithValue(api), miniAppSlotsProvider.overrideWithValue(slots)],
        child: MaterialApp(
          home: Builder(builder: (context) => const HomeShell(title: 'Super')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<MiniAppSlot> threeApps() => [
    MiniAppSlot.eager(_FakeMiniApp('feed')),
    MiniAppSlot.eager(_FakeMiniApp('chat', isGlobal: true)),
    MiniAppSlot.eager(_FakeMiniApp('communities')),
  ];

  Iterable<String> tileIds(WidgetTester tester) =>
      tester.widgetList<MiniAppTile>(find.byType(MiniAppTile)).map((t) => t.slot.info.id);

  testWidgets('shows only the mini-apps the server has on', (tester) async {
    await pumpHome(
      tester,
      threeApps(),
      server: {
        'apps': [
          {'id': 'feed', 'features': <String, bool>{}},
          {'id': 'chat', 'features': <String, bool>{}},
        ],
      },
    );
    expect(tileIds(tester), ['feed', 'chat']);
    expect(find.text('Communities'), findsNothing);
    // Chat is global: in the bar too.
    expect(find.byTooltip('Chat'), findsOneWidget);
  });

  testWidgets('never shows a mini-app this build doesn\'t have, whatever the server says', (tester) async {
    await pumpHome(
      tester,
      threeApps(),
      server: {
        'apps': [
          {'id': 'taxi'},
          {'id': 'communities'},
        ],
      },
    );
    expect(tileIds(tester), ['communities']);
    expect(find.byTooltip('Chat'), findsNothing);
  });

  testWidgets('shows every compiled-in mini-app when the server can\'t be asked', (tester) async {
    await pumpHome(tester, threeApps(), server: null);
    expect(tileIds(tester), ['feed', 'chat', 'communities']);
  });

  testWidgets('a tile opens its mini-app full screen; back returns Home', (tester) async {
    await pumpHome(tester, threeApps(), server: null);
    await tester.tap(find.text('Communities'));
    await tester.pumpAndSettle();
    expect(find.text('Communities home'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(MiniAppTile), findsNWidgets(3));
  });

  testWidgets('a deferred mini-app loads once, on first open', (tester) async {
    var loads = 0;
    final slot = MiniAppSlot.deferred(
      const MiniAppInfo(id: 'feed', name: 'Feed', icon: Icons.apps, color: Colors.teal),
      () async {
        loads++;
        return _FakeMiniApp('feed');
      },
    );
    await pumpHome(tester, [slot], server: null);
    expect(loads, 0); // the tile needs only the info
    expect(slot.loaded, isNull);

    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    expect(find.text('Feed home'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    expect(loads, 1);
  });

  testWidgets('links open another mini-app\'s screen, unless it\'s off or missing', (tester) async {
    await pumpHome(
      tester,
      threeApps(),
      server: {
        'apps': [
          {'id': 'feed'},
          {'id': 'chat'},
        ],
      },
    );
    final context = tester.element(find.byType(HomeShell));

    openAppLink(context, Uri.parse('app://feed/thing/42'));
    await tester.pumpAndSettle();
    expect(find.text('Feed thing 42'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Switched off by the server.
    openAppLink(context, AppLinks.community(9));
    await tester.pumpAndSettle();
    expect(find.text('That isn\'t available in this app.'), findsOneWidget);
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    await tester.pumpAndSettle();

    // Not in this build at all.
    openAppLink(context, Uri.parse('app://taxi/ride/1'));
    await tester.pumpAndSettle();
    expect(find.text('That isn\'t available in this app.'), findsOneWidget);
  });

  group('AppsConfig', () {
    test('reads the server\'s apps, features and map settings', () {
      final config = AppsConfig.fromJson({
        'apps': [
          {
            'id': 'communities',
            'features': {'events': true, 'tickets': false},
          },
        ],
        'maps': {
          'tileUrl': 'https://tiles.example.com/{z}/{x}/{y}.png',
          'attribution': '© Example',
          'attributionUrl': 'https://example.com/credits',
          'placeSearch': false,
          'routing': 'graphhopper',
        },
      });
      expect(config.isEnabled('communities'), isTrue);
      expect(config.isEnabled('feed'), isFalse);
      expect(config.feature('communities', 'events'), isTrue);
      expect(config.feature('communities', 'tickets'), isFalse);
      final tiles = config.maps.toTiles(userAgentPackageName: 'test');
      expect(tiles.urlTemplate, 'https://tiles.example.com/{z}/{x}/{y}.png');
      expect(tiles.attribution, '© Example');
      expect(config.maps.placeSearch, isFalse);
      expect(config.maps.routing, 'graphhopper');
    });

    test('the fallback shows everything, on OpenStreetMap', () {
      expect(AppsConfig.fallback.isEnabled('anything'), isTrue);
      expect(AppsConfig.fallback.feature('communities', 'tickets'), isTrue);
      expect(AppsConfig.fallback.maps.tileUrl, 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
    });
  });
}
