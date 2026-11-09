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
  // The server's like count after a like; null makes liking fail.
  late int? serverLikeCount;

  setUp(() {
    // Logged in as user 1 with 12 followers.
    SharedPreferences.setMockInitialValues({'id': 1, 'username': 'user_0', 'followerCount': 12});
    socket = FakeSocket();
    requests = [];
    newerPosts = [];
    serverLikeCount = 8;
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
        if (path == '/posts/20/like') {
          final count = serverLikeCount;
          if (count == null) return http.Response('{"error":"boom"}', 500);
          return http.Response(jsonEncode({'likeCount': count, 'liked': request.method == 'PUT'}), 200);
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

  test('a like shows at once, then takes the server\'s count', () async {
    final (container, sub) = await open();
    final notifier = container.read(feedProvider.notifier);

    final liking = notifier.toggleLike(20);
    expect(sub.read().posts.first.likedByMe, isTrue);
    expect(sub.read().posts.first.likeCount, 1); // straight away
    await liking;
    expect(sub.read().posts.first.likeCount, 8); // others liked it too
    expect(requests.last.method, 'PUT');

    serverLikeCount = 7;
    await notifier.toggleLike(20);
    expect(sub.read().posts.first.likedByMe, isFalse);
    expect(sub.read().posts.first.likeCount, 7);
    expect(requests.last.method, 'DELETE');
  });

  test('a like that fails is put back, and says so', () async {
    final (container, sub) = await open();
    serverLikeCount = null;
    await container.read(feedProvider.notifier).toggleLike(20);
    expect(sub.read().posts.first.likedByMe, isFalse);
    expect(sub.read().posts.first.likeCount, 0);
    expect(sub.read().error, startsWith('Couldn\'t like'));
  });

  test('reads likes and comments from the feed, and keeps the comment count in step', () async {
    final (container, sub) = await open();
    container.read(feedProvider.notifier).setCommentCount(19, 3);
    expect(sub.read().posts.firstWhere((p) => p.id == 19).commentCount, 3);
  });

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

  test('publishPost shows the new post at once, reports the fanout, and the message can be dismissed', () async {
    final (container, sub) = await open();
    final notifier = container.read(feedProvider.notifier);
    final messages = <String?>[];
    container.listen(feedProvider.select((s) => s.fanoutMessage), (_, m) => messages.add(m));

    await notifier.publishPost('  hello  ');

    expect(sub.read().posts.map((p) => p.id), [21, 20, 19]);
    expect(messages, ['Fanned out to 12 followers in 4.5 ms']);
    expect(jsonDecode(requests.last.body), {'authorId': 1, 'body': 'hello'});
    expect(requests.last.url.path, '/posts'); // no refresh: it would return the pre-fanout feed

    notifier.dismissFanoutMessage();
    expect(sub.read().fanoutMessage, isNull);
  });

  test('publishPost sends uploaded media ids in order, and allows a post with no text', () async {
    final (container, sub) = await open();

    await container.read(feedProvider.notifier).publishPost('   ', mediaIds: [9, 4]);

    expect(jsonDecode(requests.last.body), {'authorId': 1, 'body': '', 'mediaIds': [9, 4]});
    expect(sub.read().posts.first.id, 21);
  });

  test('publishPost does nothing with neither text nor media', () async {
    final (container, _) = await open();
    final before = requests.length;

    await container.read(feedProvider.notifier).publishPost('  ');

    expect(requests.length, before);
  });

  test('a refresh before the fanout lands keeps your own new post on top', () async {
    final (container, sub) = await open();
    final notifier = container.read(feedProvider.notifier);
    await notifier.publishPost('hello');

    // The fake server's feed still doesn't include post 21 (fanout pending).
    await notifier.refresh();

    expect(sub.read().posts.map((p) => p.id), [21, 20, 19]);
  });

  test('reconnecting checks for posts missed while disconnected', () async {
    final (_, sub) = await open();
    newerPosts = [post(25)];

    socket.controller.add({'type': 'reconnected'});
    await pumpEventQueue();

    expect(sub.read().hasNewPosts, isTrue);
  });
}
