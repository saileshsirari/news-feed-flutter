import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/data/services/service_providers.dart';
import 'package:news_feed_flutter/data/services/socket_provider.dart';
import 'package:news_feed_flutter/feed/comment_thread.dart';
import 'package:news_feed_flutter/feed/comments_notifier.dart';
import 'package:news_feed_flutter/feed/comments_sheet.dart';
import 'package:news_feed_flutter/models/models.dart';
import 'package:news_feed_flutter/session/current_user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_socket.dart';

/// A comment as the server sends it.
Map<String, dynamic> c(int id, String path, String body, {int? parent, int replies = 0, bool deleted = false, int author = 2}) => {
      'id': id,
      'post_id': 50,
      'parent_id': parent,
      'author_id': deleted ? 0 : author,
      'author_username': deleted ? '' : 'user$author',
      'body': deleted ? '' : body,
      'created_at': id,
      'path': path,
      'depth': path.split('.').length - 1,
      'reply_count': replies,
      'deleted': deleted,
    };

PostComment pc(Map<String, dynamic> json) => PostComment.fromJson(json);

List<String> shown(CommentThread t) => [for (final x in t.comments) '${'  ' * t.indentOf(x)}${x.deleted ? '[deleted]' : x.body}'];

void main() {
  group('a thread in reading order', () {
    CommentThread sample() => CommentThread()
      ..addPage([
        pc(c(1, '0001', 'Great post', replies: 2)),
        pc(c(2, '0001.0001', 'Agree', parent: 1, replies: 1)),
        pc(c(4, '0001.0001.0001', 'Me too', parent: 2)),
        pc(c(3, '0001.0002', 'Disagree', parent: 1)),
        pc(c(5, '0002', 'Nice photo')),
      ]);

    test('a new reply lands right after its siblings, by path', () {
      final t = sample();
      expect(t.insert(pc(c(6, '0001.0003', 'Late reply', parent: 1))), isTrue);
      expect(t.insert(pc(c(7, '0001.0001.0002', 'Me three', parent: 2))), isTrue);
      expect(t.insert(pc(c(8, '0003', 'New comment'))), isTrue);
      expect(shown(t), [
        'Great post',
        '  Agree',
        '    Me too',
        '    Me three',
        '  Disagree',
        '  Late reply',
        'Nice photo',
        'New comment',
      ]);
      expect(t.comments.first.replyCount, 3);
    });

    test('too deep to show: only the parent\'s count moves, and it links on', () {
      final t = sample();
      expect(t.insert(pc(c(9, '0001.0001.0001.0001', 'Level 3', parent: 4))), isFalse);
      expect(shown(t), isNot(contains(contains('Level 3'))));
      final meToo = t.comments.firstWhere((x) => x.id == 4);
      expect((meToo.replyCount, t.continuesElsewhere(meToo)), (1, true));
      // A reply to a comment that isn't loaded doesn't show either.
      expect(t.insert(pc(c(10, '0007.0001', 'elsewhere', parent: 77))), isFalse);
    });

    test('deleting: with replies it stays as [deleted]; without, it goes, with an emptied [deleted] parent', () {
      final t = sample();
      t.remove(2, blanked: true);
      expect(shown(t).sublist(0, 3), ['Great post', '  [deleted]', '    Me too']);
      t.remove(4, blanked: false);
      expect(shown(t), ['Great post', '  Disagree', 'Nice photo']);
      expect(t.comments.first.replyCount, 1);
    });

    test('a continued thread starts from its comment, indented from there', () {
      final t = CommentThread(root: pc(c(4, '0001.0001.0001', 'Me too', parent: 2, replies: 1)))
        ..addPage([pc(c(4, '0001.0001.0001', 'Me too', parent: 2, replies: 1)), pc(c(9, '0001.0001.0001.0001', 'L3', parent: 4))]);
      expect(shown(t), ['Me too', '  L3']);
      expect(t.insert(pc(c(11, '0001.0002', 'not in this thread', parent: 1))), isFalse);
    });
  });

  group('the comments logic, without any widgets', () {
    late FakeSocket socket;
    late ProviderContainer container;
    final post = Post(id: 50, authorId: 9, body: 'p', createdAt: 1, authorUsername: 'author', commentCount: 2);
    final key = CommentsKey(post);

    setUp(() async {
      SharedPreferences.setMockInitialValues({'id': 1, 'username': 'me', 'followerCount': 0});
      socket = FakeSocket();
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response(jsonEncode(c(20, '0003', 'mine', author: 1)), 201);
        }
        return http.Response(
          jsonEncode({
            'comments': [c(1, '0001', 'first'), c(2, '0002', 'second')],
            'nextCursor': null,
          }),
          200,
        );
      });
      container = ProviderContainer.test(overrides: [
        apiHttpClientProvider.overrideWithValue(client),
        socketProvider.overrideWith((ref, userId) => socket),
      ]);
      await container.read(currentUserProvider.future);
    });

    Future<ProviderSubscription<CommentsState>> opened() async {
      final sub = container.listen(commentsProvider(key), (_, _) {});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      return sub;
    }

    test('your own comment shows at once, and its live echo isn\'t counted twice', () async {
      final sub = await opened();
      expect(sub.read().comments.map((x) => x.body), ['first', 'second']);
      expect(await container.read(commentsProvider(key).notifier).send('mine'), isTrue);
      expect((sub.read().comments.last.body, sub.read().count), ('mine', 3));

      // The batch carries yours and someone else's.
      socket.controller.add({
        'type': 'post_comments',
        'postId': 50,
        'added': [c(20, '0003', 'mine', author: 1), c(21, '0004', 'theirs')],
        'addedCount': 2,
      });
      await Future<void>.delayed(Duration.zero);
      expect(sub.read().comments.map((x) => x.body), ['first', 'second', 'mine', 'theirs']);
      expect(sub.read().count, 4);
    });

    test('watches the post while open, and stops when nothing shows it', () async {
      final sub = await opened();
      expect(socket.watchedPosts, {50});
      sub.close();
      await Future<void>.delayed(Duration.zero);
      expect(socket.watchedPosts, isEmpty);
    });

    test('replying sets and clears who you\'re replying to', () async {
      final sub = await opened();
      final notifier = container.read(commentsProvider(key).notifier);
      notifier.startReply(sub.read().comments.first);
      expect(sub.read().replyTo?.id, 1);
      notifier.cancelReply();
      expect(sub.read().replyTo, isNull);
    });
  });

  group('the comments sheet', () {
    late FakeSocket socket;
    late List<http.Request> requests;

    setUp(() {
      SharedPreferences.setMockInitialValues({'id': 1, 'username': 'me', 'followerCount': 0});
      socket = FakeSocket();
      requests = [];
    });

    Future<ProviderContainer> open(WidgetTester tester) async {
      final client = MockClient((request) async {
        requests.add(request);
        http.Response json(Object body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status,
            headers: {'content-type': 'application/json; charset=utf-8'});
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return json(c(20, '0001.0003', body['body'] as String, parent: body['parentId'] as int?, author: 1), 201);
        }
        return json({
          'comments': [
            c(1, '0001', 'Great post', replies: 2),
            c(2, '0001.0001', 'Agree', parent: 1, replies: 1),
            c(4, '0001.0001.0001', 'Me too', parent: 2, replies: 3),
            c(3, '0001.0002', 'Disagree', parent: 1),
          ],
          'nextCursor': null,
        });
      });
      final container = ProviderContainer.test(overrides: [
        apiHttpClientProvider.overrideWithValue(client),
        socketProvider.overrideWith((ref, userId) => socket),
      ]);
      await tester.runAsync(() => container.read(currentUserProvider.future));
      final post = Post(id: 50, authorId: 9, body: 'p', createdAt: 1, authorUsername: 'author', commentCount: 4);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: CommentsSheet(post: post, onCountChanged: (_) {})),
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      return container;
    }

    testWidgets('shows threads indented, links deeper replies, and watches the post while open', (tester) async {
      await open(tester);
      expect(find.text('Great post'), findsOneWidget);
      expect(find.text('Me too'), findsOneWidget);
      expect(find.text('Continue this thread (3) →'), findsOneWidget);
      // Closing stops watching: checked in "watches the post while open, and stops…" above.
      expect(socket.watchedPosts, {50});
    });

    testWidgets('a reply goes to the comment you tapped Reply on', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('reply-1')));
      await tester.pump();
      expect(find.text('Replying to @user2'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('comment-input')), 'Good point');
      await tester.pump();
      await tester.tap(find.byTooltip('Post comment'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      final sent = requests.where((r) => r.method == 'POST').single;
      expect(jsonDecode(sent.body), {'userId': 1, 'body': 'Good point', 'parentId': 1});
      expect(find.text('Good point'), findsOneWidget);
      expect(find.text('Replying to @user2'), findsNothing);
    });

    testWidgets('live: new comments slot into place, deletions apply, overflow offers a reload', (tester) async {
      await open(tester);
      socket.controller.add({
        'type': 'post_comments',
        'postId': 50,
        'added': [c(30, '0001.0002.0001', 'Live reply', parent: 3, author: 7)],
        'addedCount': 4,
        'removed': [
          {'commentId': 2, 'blanked': true},
        ],
      });
      await tester.pump();
      expect(find.text('Live reply'), findsOneWidget);
      expect(find.text('[deleted]'), findsOneWidget);
      expect(find.text('3 new comments'), findsOneWidget);
      // Another post's changes are none of this sheet's business.
      socket.controller.add({'type': 'post_comments', 'postId': 99, 'added': [c(31, '0009', 'other')], 'addedCount': 1});
      await tester.pump();
      expect(find.text('other'), findsNothing);
    });
  });
}
