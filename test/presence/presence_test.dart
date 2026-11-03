import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/api_service.dart';
import 'package:news_feed_flutter/data/services/service_providers.dart';
import 'package:news_feed_flutter/data/services/socket_provider.dart';
import 'package:news_feed_flutter/models/models.dart';
import 'package:news_feed_flutter/presence/presence_notifier.dart';
import 'package:news_feed_flutter/presence/presence_widgets.dart';
import 'package:news_feed_flutter/session/current_user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_socket.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSocket socket;
  late List<Uri> requests;
  // What GET /presence answers, by user id.
  late Map<int, Map<String, dynamic>> server;

  setUp(() {
    SharedPreferences.setMockInitialValues({'id': 1, 'username': 'user_1', 'followerCount': 0});
    socket = FakeSocket();
    requests = [];
    server = {
      2: {'userId': 2, 'online': true, 'lastSeenAt': null},
      3: {'userId': 3, 'online': false, 'lastSeenAt': 1000},
    };
  });

  Future<ProviderContainer> makeContainer() async {
    final api = ApiService(
      AppConfig(apiBaseUrl: Uri.parse('https://example.test')),
      httpClient: MockClient((request) async {
        requests.add(request.url);
        final ids = request.url.queryParameters['userIds']!.split(',').map(int.parse);
        return http.Response(jsonEncode([for (final id in ids) server[id] ?? {'userId': id, 'online': false}]), 200);
      }),
    );
    final container = ProviderContainer.test(overrides: [
      apiServiceProvider.overrideWithValue(api),
      socketProvider.overrideWith((ref, userId) => socket),
    ]);
    await container.read(currentUserProvider.future);
    return container;
  }

  test('tracking several users at once makes one request', () async {
    final container = await makeContainer();
    final sub = container.listen(presenceProvider, (_, _) {});
    final notifier = container.read(presenceProvider.notifier);

    notifier.track([2]);
    notifier.track([3]);
    notifier.track([2]); // already tracked
    await pumpEventQueue();

    expect(requests, hasLength(1));
    expect(requests.single.queryParameters['userIds'], '2,3');
    expect(sub.read()[2]!.online, isTrue);
    expect(sub.read()[3]!.lastSeenAt, 1000);
  });

  test('presence_changed events update it live', () async {
    final container = await makeContainer();
    final sub = container.listen(presenceProvider, (_, _) {});
    container.read(presenceProvider.notifier).track([2]);
    await pumpEventQueue();

    socket.controller.add({'type': 'presence_changed', 'userId': 2, 'online': false, 'lastSeenAt': 9000});
    await pumpEventQueue();

    expect(sub.read()[2]!.online, isFalse);
    expect(sub.read()[2]!.lastSeenAt, 9000);
  });

  test('after a reconnect, everyone tracked is fetched again', () async {
    final container = await makeContainer();
    container.listen(presenceProvider, (_, _) {});
    container.read(presenceProvider.notifier).track([2, 3]);
    await pumpEventQueue();

    socket.controller.add({'type': 'reconnected'});
    await pumpEventQueue();

    expect(requests, hasLength(2));
    expect(requests.last.queryParameters['userIds']!.split(',').toSet(), {'2', '3'});
  });

  test('describes presence the way chat apps do', () {
    final now = DateTime.fromMillisecondsSinceEpoch(10 * 24 * 3600 * 1000);
    String? at(Duration ago) =>
        describePresence(Presence(userId: 1, online: false, lastSeenAt: now.subtract(ago).millisecondsSinceEpoch), now: now);

    expect(describePresence(const Presence(userId: 1, online: true)), 'online');
    expect(describePresence(null), isNull);
    expect(describePresence(const Presence(userId: 1, online: false)), isNull); // never seen
    expect(at(const Duration(seconds: 20)), 'last seen just now');
    expect(at(const Duration(minutes: 5)), 'last seen 5 min ago');
    expect(at(const Duration(hours: 3)), 'last seen 3 h ago');
    expect(at(const Duration(hours: 30)), 'last seen yesterday');
    expect(at(const Duration(days: 4)), 'last seen 4 days ago');
  });

  testWidgets('OnlineDot and PresenceSubtitle show and follow presence', (tester) async {
    final container = await tester.runAsync(makeContainer);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container!,
      child: const MaterialApp(
        home: Scaffold(
          body: Column(children: [
            OnlineDot(userId: 2, child: CircleAvatar()),
            PresenceSubtitle(userId: 2),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('online'), findsOneWidget);
    expect(find.byKey(OnlineDot.dotKey), findsOneWidget);

    socket.controller.add({'type': 'presence_changed', 'userId': 2, 'online': false, 'lastSeenAt': DateTime.now().millisecondsSinceEpoch});
    await tester.pumpAndSettle();
    expect(find.text('last seen just now'), findsOneWidget);
    expect(find.byKey(OnlineDot.dotKey), findsNothing);
  });
}
