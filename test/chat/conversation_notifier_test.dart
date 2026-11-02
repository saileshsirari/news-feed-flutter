import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/chat/conversation_notifier.dart';
import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/api_service.dart';
import 'package:news_feed_flutter/data/services/service_providers.dart';
import 'package:news_feed_flutter/data/services/socket_provider.dart';
import 'package:news_feed_flutter/session/current_user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_socket.dart';

Map<String, dynamic> message(int id, {int senderId = 2, String body = 'hi'}) => {
      'id': id,
      'conversation_id': 5,
      'sender_id': senderId,
      'body': body,
      'created_at': id,
      'sender_username': 'user_$senderId',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig(apiBaseUrl: Uri.parse('https://example.test'));

  late FakeSocket socket;
  // What the fake server currently has, newest first (like the real API).
  late List<Map<String, dynamic>> serverMessages;
  late List<http.Request> requests;

  setUp(() {
    // Logged in as user 1 (UserSession reads these keys).
    SharedPreferences.setMockInitialValues({'id': 1, 'username': 'user_0', 'followerCount': 0});
    socket = FakeSocket();
    serverMessages = [message(11), message(10)];
    requests = [];
  });

  /// A container where conversation 5 is backed by the fake server above.
  Future<ProviderContainer> openContainer() async {
    final api = ApiService(
      config,
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (request.method == 'GET' && path == '/conversations/5/messages') {
          return http.Response(jsonEncode({'messages': serverMessages, 'nextCursor': null}), 200);
        }
        if (request.method == 'GET' && path == '/conversations/5/reads') {
          return http.Response(
            jsonEncode([
              {'user_id': 1, 'last_read_message_id': 11},
              {'user_id': 2, 'last_read_message_id': 10},
            ]),
            200,
          );
        }
        if (request.method == 'POST' && path == '/conversations/5/messages') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(message(12, senderId: 1, body: body['body'] as String)), 200);
        }
        return http.Response('{}', 200); // PUT /read
      }),
    );
    final container = ProviderContainer.test(overrides: [
      apiServiceProvider.overrideWithValue(api),
      socketProvider.overrideWith((ref, userId) => socket),
    ]);
    await container.read(currentUserProvider.future);
    return container;
  }

  /// Watches conversation 5 (like the open screen does) and lets its
  /// initial requests finish.
  Future<ProviderSubscription<ConversationState>> open(ProviderContainer container) async {
    final sub = container.listen(conversationProvider(5), (_, _) {});
    await pumpEventQueue();
    return sub;
  }

  test('starts loading, then shows messages oldest-first', () async {
    final container = await openContainer();
    final sub = container.listen(conversationProvider(5), (_, _) {});

    expect(sub.read().isLoading, isTrue);

    await pumpEventQueue();
    expect(sub.read().isLoading, isFalse);
    expect(sub.read().messages.map((m) => m.id), [10, 11]);
  });

  test('read states drive the Seen tick', () async {
    final container = await openContainer();
    final sub = await open(container);

    // user 2 has read up to 10, not 11.
    expect(sub.read().isReadByOthers(10, currentUserId: 1), isTrue);
    expect(sub.read().isReadByOthers(11, currentUserId: 1), isFalse);

    socket.controller.add({'type': 'read_receipt_updated', 'conversationId': 5, 'userId': 2, 'lastReadMessageId': 11});
    await pumpEventQueue();

    expect(sub.read().isReadByOthers(11, currentUserId: 1), isTrue);
  });

  test('message_created for this conversation reloads; other conversations are ignored', () async {
    final container = await openContainer();
    final sub = await open(container);
    serverMessages = [message(13), ...serverMessages];

    socket.controller.add({'type': 'message_created', 'conversationId': 99});
    await pumpEventQueue();
    expect(sub.read().messages.map((m) => m.id), [10, 11]);

    socket.controller.add({'type': 'message_created', 'conversationId': 5});
    await pumpEventQueue();
    expect(sub.read().messages.map((m) => m.id), [10, 11, 13]);
    // ...and marks the new newest message read.
    expect(requests.last.method, 'PUT');
    expect(jsonDecode(requests.last.body)['lastReadMessageId'], 13);
  });

  test('after a reconnect, reloads messages missed while disconnected', () async {
    final container = await openContainer();
    final sub = await open(container);
    serverMessages = [message(14), ...serverMessages]; // arrived while the socket was down

    socket.controller.add({'type': 'reconnected'});
    await pumpEventQueue();

    expect(sub.read().messages.map((m) => m.id), [10, 11, 14]);
  });

  test('send appends the sent message', () async {
    final container = await openContainer();
    final sub = await open(container);

    final sending = container.read(conversationProvider(5).notifier).send('  hello  ');
    expect(sub.read().isSending, isTrue);
    await sending;

    expect(sub.read().isSending, isFalse);
    expect(sub.read().messages.last.body, 'hello');
  });

  test('closing the screen disposes the notifier and stops listening to the socket', () async {
    final container = await openContainer();
    final sub = await open(container);
    expect(socket.controller.hasListener, isTrue);

    sub.close();
    await container.pump(); // let autoDispose run

    expect(socket.controller.hasListener, isFalse);
  });
}
