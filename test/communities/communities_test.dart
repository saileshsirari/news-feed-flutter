import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/communities/communities_providers.dart';
import 'package:news_feed_flutter/communities/community.dart';
import 'package:news_feed_flutter/communities/community_screen.dart';
import 'package:news_feed_flutter/data/services/service_providers.dart';
import 'package:news_feed_flutter/session/current_user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> community({
  int id = 9,
  String visibility = 'public',
  int members = 3,
  String? myRole,
  String? myStatus,
}) =>
    {
      'id': id,
      'slug': 'bangalore-runners',
      'name': 'Bangalore Runners',
      'description': 'Sunday long runs.',
      'visibility': visibility,
      'photo': null,
      'memberCount': members,
      'createdAt': 1,
      'myRole': myRole,
      'myStatus': myStatus,
    };

Map<String, dynamic> member(int id, String role, [String status = 'active']) => {
      'user': {'id': id, 'username': 'user$id', 'created_at': 1, 'is_celebrity': false},
      'role': role,
      'status': status,
      'joinedAt': id,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.Request> requests;
  /// What GET /communities/9 says the viewer is.
  late Map<String, dynamic> served;
  setUp(() {
    SharedPreferences.setMockInitialValues({'id': 1, 'username': 'me', 'followerCount': 0});
    requests = [];
    served = community();
  });

  http.Client server() => MockClient((request) async {
        requests.add(request);
        http.Response json(Object? body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status,
            headers: {'content-type': 'application/json; charset=utf-8'});
        final path = request.url.path;
        if (path == '/communities/9' && request.method == 'GET') return json(served);
        if (path == '/communities/9/posts') return json({'posts': [], 'nextCursor': null});
        if (path == '/communities/9/join') {
          return json(community(
            visibility: served['visibility'] as String,
            members: served['visibility'] == 'public' ? 4 : 3,
            myRole: served['visibility'] == 'public' ? 'member' : null,
            myStatus: served['visibility'] == 'public' ? 'active' : 'pending',
          ));
        }
        if (path == '/communities/9/membership') return json(community());
        if (path == '/communities/joined') return json({'items': [], 'nextCursor': null});
        if (path == '/communities/9/members') {
          final pending = request.url.queryParameters['status'] == 'pending';
          return json({
            'items': pending ? [member(5, 'member', 'pending'), member(6, 'member', 'pending')] : [member(1, 'owner')],
            'nextCursor': null,
          });
        }
        if (path == '/communities/9/members/5/approve') return json(member(5, 'member'));
        if (path == '/communities') {
          final cursor = request.url.queryParameters['cursor'];
          return json(cursor == null
              ? {'items': [community(id: 1), community(id: 2)], 'nextCursor': 'next'}
              : {'items': [community(id: 3)], 'nextCursor': null});
        }
        return json({'error': 'not found'}, 404);
      });

  Future<ProviderContainer> signedIn() async {
    final container = ProviderContainer.test(overrides: [apiHttpClientProvider.overrideWithValue(server())]);
    await container.read(currentUserProvider.future);
    return container;
  }

  test('a community reads the viewer\'s place in it', () {
    final c = Community.fromJson(community(visibility: 'private', myRole: 'moderator', myStatus: 'active'));
    expect((c.isPrivate, c.isMember, c.canModerate, c.isOwner), (true, true, true, false));
    final pending = Community.fromJson(community(myStatus: 'pending'));
    expect((pending.isMember, pending.canModerate, pending.myRole), (false, false, null));
  });

  test('discovery pages through the results, as the signed-in user', () async {
    final container = await signedIn();
    final sub = container.listen(discoverCommunitiesProvider(''), (_, _) {});
    await container.read(discoverCommunitiesProvider('').future);
    await container.read(discoverCommunitiesProvider('').notifier).loadMore();
    expect(sub.read().value!.items.map((c) => c.id), [1, 2, 3]);
    expect(sub.read().value!.hasMore, isFalse);
    expect(requests.first.url.queryParameters['userId'], '1');
    expect(requests.last.url.queryParameters['cursor'], 'next');
  });

  test('joining a public community makes you a member at once; a private one, a request', () async {
    final container = await signedIn();
    final sub = container.listen(communityProvider(9), (_, _) {});
    await container.read(communityProvider(9).future);
    await container.read(communityProvider(9).notifier).join();
    expect((sub.read().value!.isMember, sub.read().value!.memberCount), (true, 4));

    served = community(visibility: 'private');
    container.invalidate(communityProvider(9));
    await container.read(communityProvider(9).future);
    await container.read(communityProvider(9).notifier).join();
    expect(sub.read().value!.myStatus, MembershipStatus.pending);
  });

  test('approving a request takes it off the list', () async {
    final container = await signedIn();
    final key = (communityId: 9, status: MembershipStatus.pending);
    final sub = container.listen(communityMembersProvider(key), (_, _) {});
    await container.read(communityMembersProvider(key).future);
    await container.read(communityMembersProvider(key).notifier).approve(5);
    expect(sub.read().value!.items.map((m) => m.user.id), [6]);
    expect(requests.any((r) => r.method == 'POST' && r.url.path == '/communities/9/members/5/approve'), isTrue);
  });

  Future<void> showCommunity(WidgetTester tester) async {
    final container = await tester.runAsync(signedIn);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container!,
      child: const MaterialApp(home: CommunityScreen(communityId: 9)),
    ));
    await tester.runAsync(() => container.read(communityProvider(9).future));
    await tester.pump();
  }

  testWidgets('someone outside a public community sees Join', (tester) async {
    await showCommunity(tester);
    expect(find.text('Join'), findsOneWidget);
    expect(find.text('Public · 3 members'), findsOneWidget);
    expect(find.text('Banned'), findsNothing); // not a moderator
  });

  testWidgets('a private one asks to join, and hides its members from outsiders', (tester) async {
    served = community(visibility: 'private');
    await showCommunity(tester);
    expect(find.text('Ask to join'), findsOneWidget);
    expect(find.text('Only members can see who\'s in it'), findsOneWidget);
  });

  testWidgets('its owner can edit it and see join requests and bans', (tester) async {
    served = community(visibility: 'private', myRole: 'owner', myStatus: 'active');
    await showCommunity(tester);
    expect(find.text('You own this community.'), findsOneWidget);
    expect(find.text('Join requests'), findsOneWidget);
    expect(find.text('Banned'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
  });
}
