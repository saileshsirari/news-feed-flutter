import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/api_service.dart';
import 'package:news_feed_flutter/data/services/service_providers.dart';
import 'package:news_feed_flutter/data/services/socket_provider.dart';
import 'package:news_feed_flutter/feed/feed_notifier.dart';
import 'package:news_feed_flutter/session/current_user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_socket.dart';

Map<String, dynamic> post(int id) =>
    {'id': id, 'author_id': 2, 'body': 'post $id', 'created_at': id, 'author_username': 'user_2'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSocket socket;
  late List<http.Request> requests;
  // GET /feed/1/new answers with these.
  late List<Map<String, dynamic>> newerPosts;

  setUp(() {
    // Logged in as user 1 with 12 followers.
    SharedPreferences.setMockInitialValues({'id': 1, 'username': 'user_0', 'followerCount': 12});
    socket = FakeSocket();
    requests = [];
    newerPosts = [];
  });

  Future<(ProviderContainer, ProviderSubscription<FeedState>)> open() async {
    final api = ApiService(
      AppConfig(apiBaseUrl: Uri.parse('https://example.test')),
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path == '/feed/1/new') {
          return http.Response(jsonEncode({'posts': newerPosts, 'newestCursor': null}), 200);
        }
        if (path == '/feed/1') {
          final firstPage = request.url.queryParameters['cursor'] == null;
          return http.Response(
            jsonEncode(firstPage
                ? {'posts': [post(20), post(19)], 'nextCursor': 'page2'}
                : {'posts': [post(18)], 'nextCursor': null}),
            200,
          );
        }
        // POST /posts
        return http.Response(jsonEncode({...post(21), 'fanoutMs': 4.5}), 201);
      }),
    );
    final container = ProviderContainer.test(overrides: [
      apiServiceProvider.overrideWithValue(api),
      socketProvider.overrideWith((ref, userId) => socket),
    ]);
    await container.read(currentUserProvider.future);
    final sub = container.listen(feedProvider, (_, _) {});
    await pumpEventQueue();
    return (container, sub);
  }

  test('loads the first page for the logged-in user', () async {
    final (_, sub) = await open();

    expect(sub.read().user.username, 'user_0');
    expect(sub.read().isLoading, isFalse);
    expect(sub.read().posts.map((p) => p.id), [20, 19]);
    expect(sub.read().nextCursor, 'page2');
  });

  test('loadMore appends the next page and stops at the end', () async {
    final (container, sub) = await open();

    await container.read(feedProvider.notifier).loadMore();

    expect(sub.read().posts.map((p) => p.id), [20, 19, 18]);
    expect(sub.read().nextCursor, isNull);
  });

  test('feed_updated shows the banner only if something is actually new', () async {
    final (_, sub) = await open();

    socket.controller.add({'type': 'feed_updated'});
    await pumpEventQueue();
    expect(sub.read().hasNewPosts, isFalse);

    newerPosts = [post(25)];
    socket.controller.add({'type': 'feed_updated'});
    await pumpEventQueue();
    expect(sub.read().hasNewPosts, isTrue);
  });

  test('publishPost reports the fanout, refreshes, and the message can be dismissed', () async {
    final (container, sub) = await open();
    final notifier = container.read(feedProvider.notifier);
    final messages = <String?>[];
    container.listen(feedProvider.select((s) => s.fanoutMessage), (_, m) => messages.add(m));

    await notifier.publishPost('  hello  ');

    expect(messages, ['Fanned out to 12 followers in 4.5 ms']);
    expect(jsonDecode(requests.firstWhere((r) => r.method == 'POST').body), {'authorId': 1, 'body': 'hello'});
    expect(requests.last.url.path, '/feed/1'); // refreshed afterwards

    notifier.dismissFanoutMessage();
    expect(sub.read().fanoutMessage, isNull);
  });
}
