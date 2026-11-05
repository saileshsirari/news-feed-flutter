import 'dart:convert';

import 'package:chat_store/chat_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/chat/conversation_screen.dart';
import 'package:news_feed_flutter/chat/local/local_chat.dart';
import 'package:news_feed_flutter/chat/search/message_search_screen.dart';
import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/api_service.dart';
import 'package:news_feed_flutter/data/services/service_providers.dart';
import 'package:news_feed_flutter/data/services/socket_provider.dart';
import 'package:news_feed_flutter/session/current_user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_chat_server.dart';
import '../helpers/fake_socket.dart';

Map<String, dynamic> message(int seq, String body) => {
  'id': 100 + seq,
  'conversation_id': 5,
  'seq': seq,
  'sender_id': 2,
  'body': body,
  'created_at': DateTime(2026, 11, 1).millisecondsSinceEpoch + seq,
  'sender_username': 'ann',
};

void main() {
  final messages = [message(1, 'Lunch at the café?'), message(2, 'The beach photos are up'), message(3, 'see you')];

  Future<void> pumpSearch(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'id': 1, 'username': 'me', 'followerCount': 0});
    final api = ApiService(
      AppConfig(apiBaseUrl: Uri.parse('https://example.test')),
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path == '/conversations') {
          return http.Response(
            jsonEncode([
              {'id': 5, 'is_group': false, 'other_username': 'ann', 'other_user_id': 2, 'unread_count': 0},
            ]),
            200,
          );
        }
        if (path == '/conversations/5/messages') return answerMessagesBySeq(request, messages);
        if (path == '/conversations/5/reads') return http.Response('[]', 200);
        return http.Response('{}', 200);
      }),
    );
    final socket = FakeSocket();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiServiceProvider.overrideWithValue(api),
          socketProvider.overrideWith((ref, userId) => socket),
          ...localChatOverrides(),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            // Signed in, and these messages already on the device.
            if (ref.watch(currentUserProvider).value == null) return const SizedBox();
            return const MaterialApp(home: MessageSearchScreen());
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(MessageSearchScreen)));
    await tester.runAsync(
      () => container.read(messageStoreProvider(1)).upsertAll([for (final m in messages) remoteMessageFrom(m)]),
    );
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('message-search')), text);
    await tester.pump(const Duration(milliseconds: 300)); // past the typing pause
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50))); // the query
    await tester.pumpAndSettle();
  }

  testWidgets('finds messages on the device, with the match in bold', (tester) async {
    await pumpSearch(tester);
    await search(tester, 'beach');

    expect(find.text('@ann'), findsOneWidget); // the chat's title
    final subtitle = tester.widget<Text>(find.byWidgetPredicate((w) => w is Text && w.textSpan != null));
    final bold = <String>[];
    subtitle.textSpan!.visitChildren((span) {
      if (span is TextSpan && span.style?.fontWeight == FontWeight.bold) bold.add(span.text!);
      return true;
    });
    expect(bold, ['beach']);

    await search(tester, 'cafe'); // accents don't matter
    expect(find.textContaining('café', findRichText: true), findsOneWidget);

    await search(tester, 'dinner');
    expect(find.textContaining('No messages on this device match', findRichText: true), findsOneWidget);
  });

  testWidgets('tapping a result opens that chat', (tester) async {
    await pumpSearch(tester);
    await search(tester, 'see');
    expect(find.byType(ListTile), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ConversationScreen), findsOneWidget);

    // Close everything and let the opened chat's background sync finish.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(seconds: 1));
  });

  test('highlighted() bolds exactly the marked words', () {
    final spans = highlighted('a ${MessageStore.matchStart}b${MessageStore.matchEnd} c');
    expect(spans.map((s) => s.text), ['a ', 'b', ' c']);
    expect(spans[1].style?.fontWeight, FontWeight.bold);
    expect(highlighted('plain').single.text, 'plain');
  });
}
