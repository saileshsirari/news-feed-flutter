import 'dart:async';
import 'dart:convert';

import 'package:chat_store/chat_store.dart';
import 'package:chat_store/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/chat/conversation_notifier.dart';
import 'package:news_feed_flutter/chat/local/background_sync.dart';
import 'package:news_feed_flutter/chat/local/local_chat.dart';
import 'package:news_feed_flutter/chat/message_info_sheet.dart';
import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/api_service.dart';
import 'package:news_feed_flutter/models/models.dart';

import '../helpers/fake_chat_server.dart';

Map<String, dynamic> message(int conversationId, int seq, {int senderId = 2}) => {
      'id': conversationId * 1000 + seq,
      'conversation_id': conversationId,
      'seq': seq,
      'sender_id': senderId,
      'body': 'm$seq',
      'created_at': seq,
      'sender_username': 'user_$senderId',
    };

void main() {
  group('ticks', () {
    // Me (1), ann (2), bob (3), in a group.
    ConversationState state({required Map<int, int> read, required Map<int, int> delivered}) =>
        ConversationState(readStateByUserId: read, deliveredByUserId: delivered);

    test('sent until everyone has it, delivered until everyone has read it', () {
      const me = 1;
      expect(state(read: {}, delivered: {}).tickFor(50, currentUserId: me), isNull); // not loaded yet
      expect(
        state(read: {1: 50, 2: 0, 3: 0}, delivered: {1: 50, 2: 50, 3: 0}).tickFor(50, currentUserId: me),
        MessageTick.sent, // bob doesn't have it
      );
      expect(
        state(read: {1: 50, 2: 50, 3: 0}, delivered: {1: 50, 2: 50, 3: 50}).tickFor(50, currentUserId: me),
        MessageTick.delivered, // bob has it, hasn't read it
      );
      expect(
        state(read: {1: 0, 2: 60, 3: 50}, delivered: {2: 60, 3: 50}).tickFor(50, currentUserId: me),
        MessageTick.read, // my own pointer doesn't matter
      );
      // An older message can be read while a newer one is only delivered.
      final mixed = state(read: {2: 40, 3: 40}, delivered: {2: 50, 3: 50});
      expect(mixed.tickFor(40, currentUserId: me), MessageTick.read);
      expect(mixed.tickFor(50, currentUserId: me), MessageTick.delivered);
    });
  });

  group('background sync', () {
    late List<Map<String, dynamic>> server5;
    late List<Map<String, dynamic>> server6;
    late List<String> delivered;
    late StreamController<Map<String, dynamic>> events;
    late ChatDatabase db;
    late ChatBackgroundSync background;

    ApiService api() => ApiService(
          AppConfig(apiBaseUrl: Uri.parse('https://example.test')),
          httpClient: MockClient((request) async {
            final path = request.url.path;
            if (path == '/conversations') {
              return http.Response(
                jsonEncode([
                  for (final (id, msgs) in [(5, server5), (6, server6)])
                    {'id': id, 'is_group': true, 'name': 'g$id', 'unread_count': 0, 'last_seq': msgs.length},
                ]),
                200,
              );
            }
            if (path == '/conversations/5/messages') return answerMessagesBySeq(request, server5);
            if (path == '/conversations/6/messages') return answerMessagesBySeq(request, server6);
            if (request.method == 'PUT' && path.endsWith('/delivered')) {
              delivered.add('${request.url.pathSegments[1]}:${jsonDecode(request.body)['lastDeliveredMessageId']}');
              return http.Response('', 204);
            }
            return http.Response('{}', 404);
          }),
        );

    Future<void> start() async {
      final store = MessageStore(db);
      final client = api();
      background = ChatBackgroundSync(
        userId: 1,
        api: client,
        sync: ChatSync(store, ApiMessageSource(client, 1)),
        store: store,
        events: events.stream,
      );
      await pumpEventQueue();
    }

    setUp(() {
      server5 = [message(5, 1), message(5, 2)];
      server6 = [];
      delivered = [];
      events = StreamController.broadcast();
      db = inMemoryChatDatabase();
    });

    tearDown(() async {
      background.dispose();
      await db.close();
    });

    test('on start, catches up on chats with news and reports them delivered', () async {
      await start();
      expect(delivered, ['5:5002']); // chat 6 is empty: nothing to fetch or report
      expect(await MessageStore(db).newestRange(5), (low: 1, high: 2));
    });

    test('a new message in any chat is stored and reported delivered, once', () async {
      await start();
      server6.add(message(6, 1));
      events.add({'type': 'message_created', 'conversationId': 6, 'seq': 1, 'senderId': 2});
      await pumpEventQueue();
      expect(delivered, ['5:5002', '6:6001']);
      expect((await MessageStore(db).watchFrom(6, 1).first).single.body, 'm1');

      // The same event again (e.g. from two sockets): no second report.
      events.add({'type': 'message_created', 'conversationId': 6, 'seq': 1, 'senderId': 2});
      await pumpEventQueue();
      expect(delivered, hasLength(2));
    });

    test('my own messages are not reported back; a reconnect catches up again', () async {
      await start();
      server5.add(message(5, 3, senderId: 1));
      events.add({'type': 'message_created', 'conversationId': 5, 'seq': 3, 'senderId': 1});
      await pumpEventQueue();
      expect(delivered, ['5:5002']);

      server5.add(message(5, 4)); // arrived while the socket was down
      events.add({'type': 'reconnected'});
      await pumpEventQueue();
      expect(delivered, ['5:5002', '5:5004']);
    });
  });

  testWidgets('Message info lists who read it, who has it, who doesn\'t yet', (tester) async {
    final message = ChatMessage.fromJson({...{'id': 50}, ...{
      'conversation_id': 5,
      'seq': 1,
      'sender_id': 1,
      'body': 'hello',
      'created_at': 0,
      'sender_username': 'me',
    }});
    const state = ConversationState(
      usernameByUserId: {1: 'me', 2: 'ann', 3: 'bob', 4: 'cat'},
      readStateByUserId: {1: 50, 2: 50, 3: 10, 4: 0},
      deliveredByUserId: {1: 50, 2: 50, 3: 50, 4: 0},
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showMessageInfo(context, message, state, 1),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    String sectionOf(String name) {
      final names = tester.widgetList<Text>(find.descendant(of: find.byKey(const Key('message-info')), matching: find.byType(Text)));
      String? section;
      for (final text in names) {
        if (['Read by', 'Delivered to', 'Not delivered yet'].contains(text.data)) section = text.data;
        if (text.data == name) return section!;
      }
      throw StateError('$name not listed');
    }

    expect(sectionOf('@ann'), 'Read by');
    expect(sectionOf('@bob'), 'Delivered to');
    expect(sectionOf('@cat'), 'Not delivered yet');
    expect(find.text('@me'), findsNothing);
  });
}
