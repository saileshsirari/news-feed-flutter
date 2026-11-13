import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/api_service.dart';
import 'package:news_feed_flutter/data/services/service_providers.dart';
import 'package:news_feed_flutter/models/models.dart';
import 'package:news_feed_flutter/profile/profile_notifier.dart';
import 'package:news_feed_flutter/profile/profile_screen.dart';
import 'package:news_feed_flutter/session/current_user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> profile({String? displayName = 'Ada Lovelace', Object? avatar}) => {
      'id': 7,
      'username': 'ada',
      'created_at': 1,
      'is_celebrity': false,
      'display_name': displayName,
      'bio': 'Writes about engines.',
      'avatar': avatar,
      'followerCount': 3,
      'followingCount': 2,
      'postCount': 3,
    };

Map<String, dynamic> post(int id) => {
      'id': id,
      'author_id': 7,
      'body': 'post $id',
      'created_at': id,
      'author_username': 'ada',
      'author_display_name': 'Ada Lovelace',
      'author_avatar': {'id': 90, 'url': 'https://bucket.test/90'},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.Request> requests;
  setUp(() {
    // Signed in as user 1 (a test account).
    SharedPreferences.setMockInitialValues({'id': 1, 'username': 'me', 'followerCount': 0});
    requests = [];
  });

  ApiService api() => ApiService(
        AppConfig(apiBaseUrl: Uri.parse('https://example.test')),
        httpClient: MockClient((request) async {
          requests.add(request);
          final path = request.url.path;
          http.Response json(Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
          if (path == '/users/7') return json(profile());
          if (path == '/users/7/posts') {
            return request.url.queryParameters['cursor'] == null
                ? json({'posts': [post(3), post(2)], 'nextCursor': 'more'})
                : json({'posts': [post(1)], 'nextCursor': null});
          }
          if (path == '/posts/3/like') return json({'likeCount': 1, 'liked': true});
          if (path == '/me/profile') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            return json(profile(displayName: body['displayName'] as String?, avatar: null));
          }
          return http.Response('{}', 404);
        }),
      );

  Future<ProviderContainer> signedIn() async {
    final container = ProviderContainer.test(overrides: [apiServiceProvider.overrideWithValue(api())]);
    await container.read(currentUserProvider.future);
    return container;
  }

  test('a profile reads its name, bio, photo and counts; posts their author\'s', () {
    final user = User.fromJson(profile(avatar: {'id': 90, 'url': 'https://bucket.test/90'}));
    expect((user.shownName, user.bio, user.photo?.id, user.followingCount, user.postCount),
        ('Ada Lovelace', 'Writes about engines.', 90, 2, 3));
    expect(User.fromJson(profile(displayName: null)).shownName, '@ada');
    final p = Post.fromJson(post(3));
    expect((p.authorDisplayName, p.authorPhoto?.url.toString()), ('Ada Lovelace', 'https://bucket.test/90'));
  });

  test('loads the person and their posts together, then more, and likes them', () async {
    final container = await signedIn();
    final sub = container.listen(profileProvider(7), (_, _) {});
    final state = await container.read(profileProvider(7).future);
    expect(state.user.displayName, 'Ada Lovelace');
    expect(state.posts.map((p) => p.id), [3, 2]);
    // The viewer is who the server marks likes for.
    expect(requests.firstWhere((r) => r.url.path == '/users/7/posts').url.queryParameters['userId'], '1');

    final notifier = container.read(profileProvider(7).notifier);
    await notifier.loadMore();
    expect(sub.read().value!.posts.map((p) => p.id), [3, 2, 1]);
    expect(sub.read().value!.nextCursor, isNull);

    await notifier.toggleLike(3);
    expect((sub.read().value!.posts.first.likedByMe, sub.read().value!.posts.first.likeCount), (true, 1));
    notifier.setCommentCount(2, 5);
    expect(sub.read().value!.posts[1].commentCount, 5);
  });

  test('saving sends only what\'s given, and a removed photo as null', () async {
    final container = await signedIn();
    final saved = await container.read(apiServiceProvider).updateProfile(userId: 1, displayName: 'Ada', removePhoto: true);
    expect(saved.displayName, 'Ada');
    final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
    expect(body, {'userId': 1, 'displayName': 'Ada', 'avatarMediaId': null});
    expect(requests.last.method, 'PATCH');

    await container.read(apiServiceProvider).updateProfile(userId: 1, bio: 'hi');
    expect(jsonDecode(requests.last.body), {'userId': 1, 'bio': 'hi'}); // the photo is left alone
  });

  testWidgets('someone else\'s profile shows Follow and Message, not Edit', (tester) async {
    final container = await tester.runAsync(signedIn);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container!,
      child: const MaterialApp(home: ProfileScreen(userId: 7)),
    ));
    await tester.runAsync(() => container.read(profileProvider(7).future));
    await tester.pump();

    expect(find.text('@ada'), findsOneWidget);
    expect(find.text('Writes about engines.'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    expect(find.text('Edit profile'), findsNothing);
    expect(find.text('post 3'), findsOneWidget);
  });
}
