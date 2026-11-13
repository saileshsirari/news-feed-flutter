import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/communities/communities_providers.dart';
import 'package:news_feed_flutter/communities/community_screen.dart';
import 'package:news_feed_flutter/data/services/service_providers.dart';
import 'package:news_feed_flutter/feed/post_card.dart';
import 'package:news_feed_flutter/models/models.dart';
import 'package:news_feed_flutter/session/current_user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A post as the server sends it, in community 9 unless [community] is false.
Map<String, dynamic> post(int id, {int author = 2, bool community = true, bool canModerate = false}) => {
      'id': id,
      'author_id': author,
      'body': 'post $id',
      'created_at': id,
      'author_username': 'user$author',
      'community_id': community ? 9 : null,
      'community': community ? {'id': 9, 'name': 'Runners', 'slug': 'runners', 'visibility': 'public'} : null,
      'can_moderate': canModerate,
    };

Map<String, dynamic> community({String visibility = 'public', String? myRole, String? myStatus}) => {
      'id': 9,
      'slug': 'runners',
      'name': 'Runners',
      'description': null,
      'visibility': visibility,
      'photo': null,
      'memberCount': 2,
      'myRole': myRole,
      'myStatus': myStatus,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.Request> requests;
  late Map<String, dynamic> served;

  setUp(() {
    SharedPreferences.setMockInitialValues({'id': 1, 'username': 'me', 'followerCount': 0});
    requests = [];
    served = community(myRole: 'member', myStatus: 'active');
  });

  http.Client server() => MockClient((request) async {
        requests.add(request);
        http.Response json(Object? body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status,
            headers: {'content-type': 'application/json; charset=utf-8'});
        final path = request.url.path;
        if (path == '/communities/9') return json(served);
        if (path == '/communities/9/posts') return json({'posts': [post(5), post(4, author: 1)], 'nextCursor': null});
        if (path == '/posts' && request.method == 'POST') return json({...post(6, author: 1), 'fanoutMs': 1.0}, 201);
        if (path.startsWith('/posts/') && request.method == 'DELETE') return http.Response('', 204);
        return json({'error': 'not found'}, 404);
      });

  Future<ProviderContainer> signedIn() async {
    final container = ProviderContainer.test(overrides: [apiHttpClientProvider.overrideWithValue(server())]);
    await container.read(currentUserProvider.future);
    return container;
  }

  test('a post knows its community, and who may delete it', () {
    final mine = Post.fromJson(post(1, author: 1));
    final theirs = Post.fromJson(post(2));
    final moderated = Post.fromJson(post(3, canModerate: true));
    expect(mine.community?.name, 'Runners');
    expect([mine.canBeDeletedBy(1), theirs.canBeDeletedBy(1), moderated.canBeDeletedBy(1)], [true, false, true]);
    expect(Post.fromJson(post(4, community: false)).community, isNull);
  });

  test('posting in a community sends it there and shows it on top; deleting takes it away', () async {
    final container = await signedIn();
    final sub = container.listen(communityPostsProvider(9), (_, _) {});
    await container.read(communityPostsProvider(9).future);
    final notifier = container.read(communityPostsProvider(9).notifier);

    await notifier.publish('  Sunday run  ', const []);
    final sent = requests.lastWhere((r) => r.method == 'POST');
    expect(jsonDecode(sent.body), {'authorId': 1, 'body': 'Sunday run', 'communityId': 9});
    expect(sub.read().value!.items.map((p) => p.id), [6, 5, 4]);

    await notifier.delete(5);
    expect(requests.last.url.path, '/posts/5');
    expect(sub.read().value!.items.map((p) => p.id), [6, 4]);
  });

  Future<void> show(WidgetTester tester, Widget child) async {
    final container = await tester.runAsync(signedIn);
    await tester.pumpWidget(UncontrolledProviderScope(container: container!, child: MaterialApp(home: child)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }

  testWidgets('in the feed a community post says where it\'s from; ⋮ only on yours or ones you moderate', (tester) async {
    Widget card(Map<String, dynamic> json) => PostCard(Post.fromJson(json), onLike: () {}, onCommentCount: (_) {}, onDelete: () {});
    await show(
      tester,
      Scaffold(body: ListView(children: [card(post(1, author: 1)), card(post(2)), card(post(3, canModerate: true))])),
    );
    expect(find.text('in Runners'), findsNWidgets(3));
    expect(find.byTooltip('Post options'), findsNWidgets(2)); // not on post 2

    await tester.tap(find.byTooltip('Post options').last);
    await tester.pumpAndSettle();
    expect(find.text('Remove post (moderator)'), findsOneWidget);
  });

  testWidgets('a member sees the community\'s posts and can write one', (tester) async {
    await show(tester, const CommunityScreen(communityId: 9));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(find.text('Write a post'), findsOneWidget);
    expect(find.text('post 5'), findsOneWidget);
    expect(find.text('in Runners'), findsNothing); // already in it
  });

  testWidgets('a private community\'s posts are kept from outsiders', (tester) async {
    served = community(visibility: 'private');
    await show(tester, const CommunityScreen(communityId: 9));
    expect(find.text('Posts in a private community are for its members.'), findsOneWidget);
    expect(find.text('Write a post'), findsNothing);
    expect(requests.where((r) => r.url.path == '/communities/9/posts'), isEmpty);
  });
}
