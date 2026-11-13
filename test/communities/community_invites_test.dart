import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/communities/community.dart';
import 'package:news_feed_flutter/communities/community_screen.dart';
import 'package:news_feed_flutter/communities/join_with_invite.dart';
import 'package:news_feed_flutter/data/services/service_providers.dart';
import 'package:news_feed_flutter/session/current_user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> community({String visibility = 'private', String? myRole, String? myStatus}) => {
      'id': 9,
      'slug': 'book-club',
      'name': 'Book club',
      'description': null,
      'visibility': visibility,
      'photo': null,
      'memberCount': 4,
      'myRole': myRole,
      'myStatus': myStatus,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.Request> requests;
  late Map<String, dynamic> served;
  late bool inviteWorks;

  setUp(() {
    SharedPreferences.setMockInitialValues({'id': 1, 'username': 'me', 'followerCount': 0});
    requests = [];
    served = community();
    inviteWorks = true;
  });

  http.Client server() => MockClient((request) async {
        requests.add(request);
        http.Response json(Object? body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status,
            headers: {'content-type': 'application/json; charset=utf-8'});
        final path = request.url.path;
        if (path == '/invites/Ab3dE5gH9k') {
          return json({'community': community(), 'works': inviteWorks, 'reason': inviteWorks ? null : 'this invite has expired'});
        }
        if (path == '/invites/Ab3dE5gH9k/accept') return json(community(myRole: 'member', myStatus: 'active'));
        if (path == '/communities/9') return json(served);
        if (path == '/communities/9/posts') return json({'posts': [], 'nextCursor': null});
        if (path == '/communities/joined') return json({'items': [], 'nextCursor': null});
        return json({'error': 'not found'}, 404);
      });

  test('the code is read from a pasted link, or taken as it is', () {
    expect(CommunityInvite.codeFrom('https://150-230-234-113.sslip.io/invite/Ab3dE5gH9k'), 'Ab3dE5gH9k');
    expect(CommunityInvite.codeFrom('Join Book club: https://x.test/invite/Ab3dE5gH9k/  '), 'Ab3dE5gH9k');
    expect(CommunityInvite.codeFrom('Ab3dE5gH9k'), 'Ab3dE5gH9k');
    expect(CommunityInvite.codeFrom('hello'), isNull);
    expect(const CommunityInvite(code: 'Ab3dE5gH9k', uses: 0).link(Uri.parse('https://api.test')), 'https://api.test/invite/Ab3dE5gH9k');
  });

  Future<void> show(WidgetTester tester, Widget home) async {
    final container = ProviderContainer.test(overrides: [apiHttpClientProvider.overrideWithValue(server())]);
    await tester.runAsync(() => container.read(currentUserProvider.future));
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(home: home)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }

  Widget opener() => Builder(
        builder: (context) => Scaffold(
          body: TextButton(onPressed: () => showJoinWithInvite(context), child: const Text('open')),
        ),
      );

  testWidgets('paste a link, see the community, join it', (tester) async {
    await show(tester, opener());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('invite-link')), 'https://x.test/invite/Ab3dE5gH9k');
    await tester.tap(find.text('Next'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(find.text('Book club'), findsOneWidget);
    expect(find.text('Private · 4 members'), findsOneWidget);

    await tester.tap(find.text('Join Book club'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(requests.any((r) => r.method == 'POST' && r.url.path == '/invites/Ab3dE5gH9k/accept'), isTrue);
  });

  testWidgets('an expired invite says so, and offers no Join', (tester) async {
    inviteWorks = false;
    await show(tester, opener());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('invite-link')), 'Ab3dE5gH9k');
    await tester.tap(find.text('Next'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(find.text('this invite has expired'), findsOneWidget);
    expect(find.text('Join Book club'), findsNothing);
  });

  testWidgets('members see the chat; moderators also see invite links', (tester) async {
    served = community(myRole: 'member', myStatus: 'active');
    await show(tester, const CommunityScreen(communityId: 9));
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Invite links'), findsNothing);
  });

  testWidgets('the owner sees invite links', (tester) async {
    served = community(myRole: 'owner', myStatus: 'active');
    await show(tester, const CommunityScreen(communityId: 9));
    expect(find.text('Invite links'), findsOneWidget);
  });

  testWidgets('outsiders see neither', (tester) async {
    await show(tester, const CommunityScreen(communityId: 9));
    expect(find.text('Chat'), findsNothing);
    expect(find.text('Invite links'), findsNothing);
  });
}
