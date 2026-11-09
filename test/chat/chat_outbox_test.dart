import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/chat/chat_outbox.dart';
import 'package:news_feed_flutter/chat/conversation_notifier.dart';
import 'package:news_feed_flutter/chat/message_sender.dart';
import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/api_service.dart';
import 'package:news_feed_flutter/data/services/service_providers.dart';
import 'package:news_feed_flutter/data/services/socket_provider.dart';
import 'package:news_feed_flutter/session/current_user_provider.dart';
import 'package:shared_media/shared_media.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_chat_server.dart';
import '../helpers/fake_socket.dart';

/// Each upload waits until the test finishes or fails it.
class FakeUploads implements MediaUploadService {
  final pending = <Completer<MediaAttachment>>[];
  var _nextId = 40;

  @override
  Future<SealedAttachment> uploadSealed(PickedMedia media, MediaSealer sealer, {void Function(double progress)? onProgress}) =>
      throw UnimplementedError();

  @override
  Future<MediaAttachment> upload(PickedMedia media, {void Function(double progress)? onProgress}) {
    final completer = Completer<MediaAttachment>();
    pending.add(completer);
    return completer.future;
  }

  void finish(int index) => pending[index].complete(MediaAttachment(
        id: _nextId++,
        kind: MediaKind.image,
        url: Uri.parse('https://bucket.test/view'),
        contentType: 'image/jpeg',
        sizeBytes: 1,
      ));

  void fail(int index) => pending[index].completeError(Exception('offline'));
}

final photo = PickedMedia(bytes: Uint8List(10), contentType: 'image/jpeg');
const draftKey = (id: 'chat:5:0', maxItems: 10, sealed: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeUploads uploads;
  late List<Map<String, dynamic>> posts;
  // How many message POSTs fail with a dropped connection before one gets through.
  late int failingPosts;
  late ProviderContainer container;
  late List<Map<String, dynamic>> serverMessages;
  var nextMessageId = 100;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'id': 1, 'username': 'user_0', 'followerCount': 0});
    retryDelay = Duration.zero;
    uploads = FakeUploads();
    posts = [];
    serverMessages = [];
    failingPosts = 0;
    final socket = FakeSocket();
    final api = ApiService(
      AppConfig(apiBaseUrl: Uri.parse('https://example.test')),
      httpClient: MockClient((request) async {
        if (request.method == 'POST' && request.url.path == '/conversations/5/messages') {
          if (failingPosts > 0) {
            failingPosts--;
            throw http.ClientException('Connection reset by peer');
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          posts.add(body);
          final sent = {
            'id': nextMessageId,
            'conversation_id': 5,
            'seq': serverMessages.length + 1,
            'sender_id': 1,
            'body': body['body'],
            'created_at': nextMessageId++,
            'sender_username': 'user_0',
          };
          serverMessages.add(sent);
          return http.Response(jsonEncode(sent), 201);
        }
        if (request.url.path == '/conversations/5/messages') return answerMessagesBySeq(request, serverMessages);
        if (request.url.path == '/conversations/5/reads') return http.Response('[]', 200);
        return http.Response('{}', 200);
      }),
    );
    container = ProviderContainer.test(overrides: [
      apiServiceProvider.overrideWithValue(api),
      socketProvider.overrideWith((ref, userId) => socket),
      mediaUploadServiceProvider.overrideWithValue(uploads),
      ...localChatOverrides(),
    ]);
    await container.read(currentUserProvider.future);
  });

  /// Like the chat screen: a photo picked in the composer, then Send.
  ChatOutboxNotifier sendWithPhoto(String text) {
    final composer = container.listen(mediaDraftProvider(draftKey), (_, _) {}); // the composer watching its draft
    container.read(mediaDraftProvider(draftKey).notifier).add(photo);
    final outbox = container.read(chatOutboxProvider(5).notifier);
    outbox.send(text, draftKey);
    composer.close(); // the composer moves on to a new draft
    return outbox;
  }

  ChatOutboxState outboxState() => container.read(chatOutboxProvider(5));

  test('waits for the upload, then sends the message with its media', () async {
    final watch = container.listen(chatOutboxProvider(5), (_, _) {});
    sendWithPhoto('look');

    expect(watch.read().pending.single.status, PendingStatus.uploading);
    expect(posts, isEmpty);

    uploads.finish(0);
    await pumpEventQueue();

    expect(posts.single['mediaIds'], [40]);
    expect(posts.single['body'], 'look');
    expect(posts.single['clientMessageId'], isA<String>());
    expect(watch.read().pending, isEmpty);
    expect(watch.read().sent.single.body, 'look');
  });

  test('text sent meanwhile goes out at once, before the message still uploading', () async {
    container.listen(chatOutboxProvider(5), (_, _) {});
    container.listen(conversationProvider(5), (_, _) {});
    sendWithPhoto('photo');

    await container.read(conversationProvider(5).notifier).send('quick text');
    expect(posts.map((p) => p['body']), ['quick text']);

    uploads.finish(0);
    await pumpEventQueue();
    expect(posts.map((p) => p['body']), ['quick text', 'photo']);
  });

  test('once sent, it appears in the open chat', () async {
    final chat = container.listen(conversationProvider(5), (_, _) {});
    await pumpEventQueue();
    sendWithPhoto('look');
    uploads.finish(0);
    await pumpEventQueue();

    expect(chat.read().messages.map((m) => m.body), ['look']);
  });

  test('a failed upload marks it failed; retry uploads again and then sends', () async {
    final watch = container.listen(chatOutboxProvider(5), (_, _) {});
    final outbox = sendWithPhoto('look');
    uploads.fail(0);
    await pumpEventQueue();

    final failed = watch.read().pending.single;
    expect(failed.status, PendingStatus.failed);
    expect(failed.error, contains('retry'));

    outbox.retry(failed.clientMessageId);
    expect(watch.read().pending.single.status, PendingStatus.uploading);
    uploads.finish(1);
    await pumpEventQueue();
    expect(posts, hasLength(1));
  });

  test('a send that keeps failing can be retried, with the same client id', () async {
    final watch = container.listen(chatOutboxProvider(5), (_, _) {});
    final outbox = sendWithPhoto('look');
    failingPosts = 2; // the send and its automatic retry
    uploads.finish(0);
    await pumpEventQueue();

    final failed = watch.read().pending.single;
    expect(failed.status, PendingStatus.failed);
    expect(failed.error, 'Couldn\'t send');

    outbox.retry(failed.clientMessageId);
    await pumpEventQueue();
    expect(posts.single['clientMessageId'], failed.clientMessageId);
    expect(watch.read().pending, isEmpty);
  });

  test('keeps uploading and sends after you leave the chat', () async {
    final screen = container.listen(chatOutboxProvider(5), (_, _) {});
    sendWithPhoto('look');
    screen.close(); // back to the chat list: nothing watches the outbox now
    await pumpEventQueue();

    uploads.finish(0);
    await pumpEventQueue();
    expect(posts.single['body'], 'look');
  });

  test('discard drops it without sending', () async {
    final watch = container.listen(chatOutboxProvider(5), (_, _) {});
    final outbox = sendWithPhoto('look');
    outbox.discard(watch.read().pending.single.clientMessageId);
    uploads.finish(0);
    await pumpEventQueue();

    expect(watch.read().pending, isEmpty);
    expect(posts, isEmpty);
    expect(outboxState().sent, isEmpty);
  });
}
