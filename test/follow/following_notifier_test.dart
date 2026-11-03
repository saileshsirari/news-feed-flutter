import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/api_service.dart';
import 'package:news_feed_flutter/data/services/service_providers.dart';
import 'package:news_feed_flutter/follow/follow_button.dart';
import 'package:news_feed_flutter/follow/following_notifier.dart';
import 'package:news_feed_flutter/session/current_user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.Request> requests;
  late Set<int> serverFollowing;
  // Set to make follow/unfollow requests fail, or wait until completed.
  int failStatus = 0;
  Completer<void>? holdChanges;

  setUp(() {
    // Logged in as user 1, who follows user 3.
    SharedPreferences.setMockInitialValues({'id': 1, 'username': 'user_1', 'followerCount': 0});
    requests = [];
    serverFollowing = {3};
    failStatus = 0;
    holdChanges = null;
  });

  ProviderContainer makeContainer() {
    final api = ApiService(
      AppConfig(apiBaseUrl: Uri.parse('https://example.test')),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') return http.Response(jsonEncode(serverFollowing.toList()), 200);
        await holdChanges?.future;
        if (failStatus != 0) return http.Response('nope', failStatus);
        final followee = (jsonDecode(request.body) as Map<String, dynamic>)['followeeId'] as int;
        request.method == 'POST' ? serverFollowing.add(followee) : serverFollowing.remove(followee);
        return http.Response('', 204);
      }),
    );
    return ProviderContainer.test(overrides: [apiServiceProvider.overrideWithValue(api)]);
  }

  Future<(ProviderContainer, ProviderSubscription<FollowingState>)> open() async {
    final container = makeContainer();
    await container.read(currentUserProvider.future);
    final sub = container.listen(followingProvider, (_, _) {});
    await pumpEventQueue();
    return (container, sub);
  }

  test('loads who the user follows', () async {
    final (_, sub) = await open();
    expect(requests.single.url.path, '/users/1/following');
    expect(sub.read().isLoaded, isTrue);
    expect(sub.read().follows(3), isTrue);
    expect(sub.read().follows(2), isFalse);
  });

  test('follow and unfollow send the right requests', () async {
    final (container, sub) = await open();
    final notifier = container.read(followingProvider.notifier);

    expect(await notifier.toggle(2), isTrue);
    expect(requests.last.method, 'POST');
    expect(jsonDecode(requests.last.body), {'followerId': 1, 'followeeId': 2});
    expect(sub.read().follows(2), isTrue);

    expect(await notifier.toggle(3), isTrue);
    expect(requests.last.method, 'DELETE');
    expect(requests.last.url.path, '/follows');
    expect(sub.read().follows(3), isFalse);
    expect(serverFollowing, {2});
  });

  test('shows the change at once, and ignores taps while it is being sent', () async {
    final (container, sub) = await open();
    final notifier = container.read(followingProvider.notifier);
    holdChanges = Completer();

    final pending = notifier.toggle(2);
    expect(sub.read().follows(2), isTrue);
    expect(sub.read().isPending(2), isTrue);
    expect(await notifier.toggle(2), isFalse); // a second tap mid-request does nothing

    holdChanges!.complete();
    expect(await pending, isTrue);
    expect(sub.read().isPending(2), isFalse);
    expect(requests.where((r) => r.method == 'POST'), hasLength(1));
  });

  test('undoes the change if the server refuses it', () async {
    final (container, sub) = await open();
    failStatus = 500;

    expect(await container.read(followingProvider.notifier).toggle(2), isFalse);
    expect(sub.read().follows(2), isFalse);
    expect(await container.read(followingProvider.notifier).toggle(3), isFalse);
    expect(sub.read().follows(3), isTrue);
  });

  testWidgets('FollowButton shows the state and says when it fails', (tester) async {
    final container = makeContainer();
    await tester.runAsync(() => container.read(currentUserProvider.future));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: Column(children: [
            FollowButton(userId: 2, username: 'user_2'),
            FollowButton(userId: 3, username: 'user_3'),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Follow'), findsOneWidget);
    expect(find.text('Following'), findsOneWidget);

    failStatus = 500;
    await tester.tap(find.text('Follow'));
    await tester.pumpAndSettle();
    expect(find.text('Couldn\'t follow @user_2. Try again.'), findsOneWidget);
    expect(find.text('Follow'), findsOneWidget);
  });
}
