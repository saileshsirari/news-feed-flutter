import 'dart:async';
import 'dart:convert';

import 'package:app_core/app_core.dart';
import 'package:app_core/config/app_config.dart';
import 'package:app_core/data/services/service_providers.dart';
import 'package:app_core/orgs/join_org_dialog.dart';
import 'package:app_core/orgs/org_header_client.dart';
import 'package:app_core/push/local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Organisations in the app: picking which one to show, switching (every
/// request then says X-Org), joining with an invite, and the switcher.
void main() {
  final config = AppConfig(apiBaseUrl: Uri.parse('https://example.test'));

  Map<String, Object?> org(int id, String name, {String role = 'member'}) => {
    'id': id,
    'slug': name.toLowerCase().replaceAll(' ', '-'),
    'name': name,
    'logo': null,
    'myRole': role,
  };

  /// A fake server: my orgs, invites, and anything else (which records the X-Org it was sent).
  late List<Map<String, Object?>> myOrgs;
  late List<String?> orgHeaders;

  http.Response server(http.Request r) {
    switch (r.url.path) {
      case '/orgs':
        return http.Response(jsonEncode({'orgs': myOrgs}), 200);
      case '/org-invites/AbCdEfGhIjKl':
        return http.Response(
          jsonEncode({'org': org(5, 'Acme Taxis')..['myRole'] = null, 'usable': true, 'problem': null}),
          200,
        );
      case '/org-invites/AbCdEfGhIjKl/accept':
        myOrgs = [...myOrgs, org(5, 'Acme Taxis')];
        return http.Response(jsonEncode(org(5, 'Acme Taxis')), 200);
      default:
        orgHeaders.add(r.headers['X-Org']);
        return http.Response('{"apps": []}', 200);
    }
  }

  setUp(() {
    // Signed in as a test account (no Zitadel): id 7.
    SharedPreferences.setMockInitialValues({'id': 7, 'username': 'asha', 'followerCount': 0});
    myOrgs = [org(1, 'Beautiful Apps'), org(5, 'Acme Taxis', role: 'owner')];
    orgHeaders = [];
  });

  List<Override> overrides() => [
    appConfigProvider.overrideWithValue(config),
    authSessionProvider.overrideWithValue(null),
    accountHttpClientProvider.overrideWithValue(MockClient((r) async => server(r))),
  ];

  group('OrgInvite.codeFrom', () {
    test('reads the code from a link or on its own', () {
      expect(OrgInvite.codeFrom('https://api.example/join/AbCdEfGhIjKl'), 'AbCdEfGhIjKl');
      expect(OrgInvite.codeFrom('Join Acme: https://api.example/join/AbCdEfGhIjKl/ '), 'AbCdEfGhIjKl');
      expect(OrgInvite.codeFrom('AbCdEfGhIjKl'), 'AbCdEfGhIjKl');
    });

    test('isn\'t fooled by a community invite (10 letters) or nonsense', () {
      expect(OrgInvite.codeFrom('https://api.example/invite/AbCdEfGhIj'), isNull);
      expect(OrgInvite.codeFrom('hello'), isNull);
    });
  });

  test('OrgHeaderClient names the org on every request, and nothing before there is one', () async {
    final seen = <String?>[];
    final inner = MockClient((r) async {
      seen.add(r.headers['X-Org']);
      return http.Response('', 200);
    });
    await OrgHeaderClient(inner, 5).get(Uri.parse('https://example.test/feed'));
    await OrgHeaderClient(inner, null).get(Uri.parse('https://example.test/feed'));
    expect(seen, ['5', null]);
  });

  group('OrgsController', () {
    test('starts in Beautiful Apps, and every request says so', () async {
      final container = ProviderContainer.test(overrides: overrides());
      final state = await container.read(orgsProvider.future);
      expect(state.orgs.map((o) => o.name), ['Beautiful Apps', 'Acme Taxis']);
      expect(state.current?.name, 'Beautiful Apps');
      await container.read(apiServiceProvider).getAppsConfig();
      expect(orgHeaders, ['1']);
    });

    test('switching changes X-Org on every request after, and is remembered', () async {
      final container = ProviderContainer.test(overrides: overrides());
      await container.read(orgsProvider.future);
      await container.read(orgsProvider.notifier).switchTo(5);
      expect(container.read(currentOrgIdProvider), 5);
      await container.read(apiServiceProvider).getAppsConfig();
      expect(orgHeaders, ['5']);

      // Next start: the same org again.
      final again = ProviderContainer.test(overrides: overrides());
      expect((await again.read(orgsProvider.future)).current?.name, 'Acme Taxis');
    });

    test('someone not in Beautiful Apps starts in their first org', () async {
      myOrgs = [org(5, 'Acme Taxis')];
      final container = ProviderContainer.test(overrides: overrides());
      expect((await container.read(orgsProvider.future)).currentId, 5);
    });

    test('a server from before organisations: no orgs, and no X-Org', () async {
      final container = ProviderContainer.test(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          authSessionProvider.overrideWithValue(null),
          accountHttpClientProvider.overrideWithValue(
            MockClient((r) async {
              if (r.url.path == '/orgs') return http.Response('not found', 404);
              orgHeaders.add(r.headers['X-Org']);
              return http.Response('{"apps": []}', 200);
            }),
          ),
        ],
      );
      expect((await container.read(orgsProvider.future)).orgs, isEmpty);
      await container.read(apiServiceProvider).getAppsConfig();
      expect(orgHeaders, [null]);
    });

    test('joining with an invite switches to the new org', () async {
      myOrgs = [org(1, 'Beautiful Apps')];
      final container = ProviderContainer.test(overrides: overrides());
      await container.read(orgsProvider.future);
      final joined = await container.read(orgsProvider.notifier).join('AbCdEfGhIjKl');
      expect(joined.name, 'Acme Taxis');
      final state = container.read(orgsProvider).requireValue;
      expect(state.orgs.map((o) => o.id), [1, 5]);
      expect(state.currentId, 5);
    });
  });

  group('on Home', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: const MaterialApp(home: Scaffold(appBar: _OrgBar())),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the title is the org shown; the switcher lists mine and switches', (tester) async {
      await pump(tester);
      expect(find.text('Beautiful Apps'), findsOneWidget);
      await tester.tap(find.text('Beautiful Apps'));
      await tester.pumpAndSettle();
      expect(find.text('Your organisations'), findsOneWidget);
      // Acme: I own it, so I may invite people to... Beautiful Apps? No: only to the one shown.
      expect(find.textContaining('Invite people'), findsNothing);
      await tester.tap(find.text('Acme Taxis'));
      await tester.pumpAndSettle();
      expect(find.text('Acme Taxis'), findsOneWidget);
      await tester.tap(find.text('Acme Taxis'));
      await tester.pumpAndSettle();
      expect(find.text('Invite people to Acme Taxis'), findsOneWidget);
    });

    testWidgets('joining: paste the link, see the org, join, and it\'s shown', (tester) async {
      myOrgs = [org(1, 'Beautiful Apps')];
      await pump(tester);
      await tester.tap(find.text('Beautiful Apps'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join with an invite'));
      await tester.pumpAndSettle();
      expect(find.byType(JoinOrgDialog), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'https://example.test/join/AbCdEfGhIjKl');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Join Acme Taxis?'), findsOneWidget);
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      expect(find.byType(JoinOrgDialog), findsNothing);
      expect(find.text('You\'re in Acme Taxis'), findsOneWidget);
      expect(find.widgetWithText(OrgTitle, 'Acme Taxis'), findsOneWidget);
    });
  });

  test('a notification shown for a push says which org it\'s about', () {
    final link = Uri.parse('app://chat/conversation/3?seq=9');
    expect(withPushOrg(link), link);
    final tagged = runZoned(() => withPushOrg(link), zoneValues: {pushOrgKey: 5});
    expect(tagged!.queryParameters, {'seq': '9', 'org': '5'});
  });
}

class _OrgBar extends StatelessWidget implements PreferredSizeWidget {
  const _OrgBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(title: const OrgTitle(fallback: 'Super'));
}
