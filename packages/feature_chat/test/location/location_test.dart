import 'dart:async';
import 'dart:convert';

import 'package:app_core/config/app_config.dart';
import 'package:app_core/data/services/api_service.dart';
import 'package:app_core/data/services/service_providers.dart';
import 'package:app_core/data/services/socket_provider.dart';
import 'package:app_core/geo/geo_services.dart';
import 'package:app_core/models/models.dart';
import 'package:app_core/session/current_user_provider.dart';
import 'package:app_core/testing/fake_socket.dart';
import 'package:feature_chat/chat/conversation_notifier.dart';
import 'package:feature_chat/chat/message_sender.dart';
import 'package:feature_chat/e2e/e2e_chats.dart';
import 'package:feature_chat/location/chat_location.dart';
import 'package:feature_chat/location/live_sealing.dart';
import 'package:feature_chat/location/location_sharing.dart';
import 'package:feature_chat/location/location_widgets.dart';
import 'package:feature_chat/testing/fake_chat_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_kit/geo_kit.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ids 10, 11, ... are seqs 1, 2, ... in conversation 5 (as in the conversation tests).
Map<String, dynamic> message(int id, {int senderId = 2, String body = '', Map<String, Object?>? location}) => {
  'id': id,
  'conversation_id': 5,
  'seq': id - 9,
  'sender_id': senderId,
  'body': body,
  'created_at': id,
  'sender_username': 'user_$senderId',
  'location': ?location,
};

class FakeGps implements AccurateLocationSource {
  const FakeGps(this.point);
  final GeoPoint point;
  @override
  Future<GeoPoint> current() async => point;
  @override
  Future<({GeoPoint point, double accuracyMetres})> currentWithAccuracy() async => (point: point, accuracyMetres: 5.0);
}

class FakeTracker implements LocationTracker {
  final controller = StreamController<GeoPoint>.broadcast();
  String? notification;
  @override
  Stream<GeoPoint> track({
    required Duration every,
    required String notificationTitle,
    required String notificationText,
  }) {
    notification = notificationTitle;
    return controller.stream;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig(apiBaseUrl: Uri.parse('https://example.test'));
  final noida = const GeoPoint(28.570123, 77.326456);

  group('the model', () {
    test('a place, a live share, an encrypted live share\'s key, and its stop', () {
      final place = ChatMessage.fromJson(
        message(10, location: {'lat': 28.57, 'lng': 77.32, 'name': 'Sector 18 Market'}),
      );
      expect(ChatLocation.of(place)!.title, 'Sector 18 Market');
      expect(ChatLocation.of(place)!.isLive, isFalse);

      final until = DateTime.now().add(const Duration(minutes: 15)).millisecondsSinceEpoch;
      final live = ChatMessage.fromJson(
        message(
          11,
          location: {
            'lat': 1,
            'lng': 2,
            'live': {'until': until, 'stoppedAt': null, 'key': base64Encode(List.filled(32, 7))},
          },
        ),
      );
      final location = ChatLocation.of(live)!;
      expect(location.isLive, isTrue);
      expect(location.runningAt(DateTime.now()), isTrue);
      expect(location.liveKey, List.filled(32, 7));
      expect(location.title, 'Live location');

      expect(ChatLocation.stopOf(ChatMessage.fromJson({...message(12), 'location_stop': 11})), 11);
      expect(ChatLocation.of(ChatMessage.fromJson(message(13, body: 'hi'))), isNull);
    });

    test('time left reads plainly', () {
      expect(timeLeft(const Duration(minutes: 47)), '47 min left');
      expect(timeLeft(const Duration(minutes: 125)), '2 h 5 min left');
      expect(timeLeft(const Duration(hours: 8)), '8 h left');
      expect(timeLeft(Duration.zero), '0 min left');
    });

    test('an encrypted chat\'s message types become stored fields', () {
      expect(
        E2eChats.extrasOf({
          'type': 'location',
          'location': {'lat': 1, 'lng': 2},
        }),
        {
          'location': {'lat': 1, 'lng': 2},
        },
      );
      expect(E2eChats.extrasOf({'type': 'location_stop', 'shareId': 99}), {'location_stop': 99});
      expect(E2eChats.extrasOf({'type': 'text', 'body': 'hi'}), isEmpty);
    });
  });

  group('sealing live positions (encrypted chats)', () {
    test('only the share\'s key opens them, and any change is caught', () async {
      final sealer = LiveUpdateSealer();
      final key = LiveUpdateSealer.newKey();
      expect(key, hasLength(32));
      final sealed = await sealer.seal(key, {'shareId': 11, 'lat': 28.57, 'lng': 77.32, 'at': 5});
      expect(sealed, isNot(contains('28.57')));
      expect(await sealer.open(key, sealed), {'shareId': 11, 'lat': 28.57, 'lng': 77.32, 'at': 5});
      expect(await sealer.open(LiveUpdateSealer.newKey(), sealed), isNull);
      final bytes = base64Decode(sealed)..[20] ^= 1;
      expect(await sealer.open(key, base64Encode(bytes)), isNull);
    });
  });

  group('in a normal chat', () {
    late FakeSocket socket;
    late FakeTracker tracker;
    late List<Map<String, dynamic>> serverMessages;
    late List<http.Request> requests;
    late List<Uri> launched;

    setUp(() {
      retryDelay = Duration.zero;
      SharedPreferences.setMockInitialValues({'id': 1, 'username': 'user_0', 'followerCount': 0});
      socket = FakeSocket();
      tracker = FakeTracker();
      serverMessages = [message(10, body: 'hi')];
      requests = [];
      launched = [];
    });

    http.Client server() => MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (request.method == 'GET' && path == '/conversations/5/messages') {
        return answerMessagesBySeq(request, serverMessages);
      }
      if (request.method == 'GET' && path == '/conversations/5/reads') return http.Response('[]', 200);
      if (request.method == 'GET' && path == '/conversations/5/live-location') return http.Response('[]', 200);
      if (request.method == 'POST' && path == '/conversations/5/messages') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final input = body['location'] as Map<String, dynamic>;
        final minutes = input['liveMinutes'] as int?;
        final sent = message(
          11 + serverMessages.length - 1,
          senderId: 1,
          location: {
            'lat': input['lat'],
            'lng': input['lng'],
            'name': ?input['name'],
            if (minutes != null)
              'live': {
                'until': DateTime.now().add(Duration(minutes: minutes)).millisecondsSinceEpoch,
                'stoppedAt': null,
              },
          },
        );
        serverMessages = [...serverMessages, sent];
        return http.Response(jsonEncode(sent), 201);
      }
      return http.Response('{"ok":true}', 200);
    });

    Future<ProviderContainer> openContainer() async {
      final client = server();
      final container = ProviderContainer.test(
        overrides: [
          apiHttpClientProvider.overrideWithValue(client),
          apiServiceProvider.overrideWithValue(ApiService(config, httpClient: client)),
          socketProvider.overrideWith((ref, userId) => socket),
          chatPreciseLocationProvider.overrideWithValue(FakeGps(noida)),
          chatTrackerProvider.overrideWithValue(tracker),
          liveUpdateIntervalProvider.overrideWithValue(Duration.zero),
          chatLinkLauncherProvider.overrideWithValue((link) async {
            launched.add(link);
            return true;
          }),
          mapTilesProvider.overrideWithValue(MapTiles.none),
          ...localChatOverrides(),
        ],
      );
      await container.read(currentUserProvider.future);
      container.listen(conversationProvider(5), (_, _) {});
      container.listen(liveViewProvider(5), (_, _) {});
      await pumpEventQueue();
      return container;
    }

    List<Map<String, dynamic>> posted(String path) => [
      for (final r in requests)
        if (r.method == 'POST' && r.url.path == path)
          r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>,
    ];

    test('sharing a place: a message with its location and no text', () async {
      final container = await openContainer();
      final sent = await container.read(conversationProvider(5).notifier).sendLocation({
        'lat': 28.5355,
        'lng': 77.391,
        'name': 'Sector 18 Market',
      });
      expect(posted('/conversations/5/messages').single, {
        'senderId': 1,
        'body': '',
        'clientMessageId': isA<String>(),
        'location': {'lat': 28.5355, 'lng': 77.391, 'name': 'Sector 18 Market'},
      });
      expect(ChatLocation.of(sent!)!.title, 'Sector 18 Market');
      await pumpEventQueue();
      expect(container.read(conversationProvider(5)).messages.map((m) => ChatLocation.of(m)?.title), [
        null,
        'Sector 18 Market',
      ]);
    });

    test('a live share: started from where I am, my positions sent as I move, then stopped', () async {
      final container = await openContainer();
      final shares = container.read(liveShareProvider.notifier);
      expect(await shares.start(5, const Duration(hours: 1), isE2e: false), isNull);

      final start = posted('/conversations/5/messages').single['location'] as Map<String, dynamic>;
      expect(start, {'lat': noida.lat, 'lng': noida.lng, 'liveMinutes': 60});
      final share = container.read(liveShareProvider)[5]!;
      expect(share.messageId, 11);
      expect(share.isE2e, isFalse);
      expect(tracker.notification, 'Sharing live location');

      tracker.controller.add(const GeoPoint(28.571, 77.327));
      await pumpEventQueue();
      expect(posted('/conversations/5/live-location/11').single, {'lat': 28.571, 'lng': 77.327});

      await shares.stop(5);
      expect(posted('/conversations/5/live-location/11/stop'), hasLength(1));
      expect(container.read(liveShareProvider), isEmpty);
      expect(tracker.controller.hasListener, isFalse); // GPS (and its notification) off
    });

    test('watching: positions arrive live, and the dot goes when they stop', () async {
      final until = DateTime.now().add(const Duration(minutes: 15)).millisecondsSinceEpoch;
      serverMessages = [
        message(
          10,
          location: {
            'lat': 28.57,
            'lng': 77.32,
            'live': {'until': until, 'stoppedAt': null},
          },
        ),
      ];
      final container = await openContainer();
      socket.controller.add({
        'type': 'live_location',
        'conversationId': 5,
        'messageId': 10,
        'senderId': 2,
        'lat': 28.58,
        'lng': 77.33,
        'at': 1,
      });
      await pumpEventQueue();
      expect(container.read(liveViewProvider(5)).points[10]!.point, const GeoPoint(28.58, 77.33));
      // Another chat's positions aren't this one's.
      socket.controller.add({
        'type': 'live_location',
        'conversationId': 6,
        'messageId': 99,
        'senderId': 2,
        'lat': 1,
        'lng': 1,
        'at': 1,
      });
      await pumpEventQueue();
      expect(container.read(liveViewProvider(5)).points.keys, [10]);

      socket.controller.add({'type': 'live_location_stopped', 'conversationId': 5, 'messageId': 10, 'senderId': 2});
      await pumpEventQueue();
      final view = container.read(liveViewProvider(5));
      expect(view.points, isEmpty);
      final msg = container.read(conversationProvider(5)).messages.single;
      expect(liveShareEnded(msg, ChatLocation.of(msg)!, view, [msg]), isTrue);
    });

    test('an encrypted chat\'s sealed position opens with the key from the share\'s message', () async {
      final key = LiveUpdateSealer.newKey();
      final until = DateTime.now().add(const Duration(minutes: 15)).millisecondsSinceEpoch;
      serverMessages = [
        message(
          10,
          location: {
            'lat': 28.57,
            'lng': 77.32,
            'live': {'until': until, 'stoppedAt': null, 'key': base64Encode(key)},
          },
        ),
      ];
      final container = await openContainer();
      final sealed = await LiveUpdateSealer().seal(key, {'shareId': 10, 'lat': 28.59, 'lng': 77.34, 'at': 2});
      socket.controller.add({
        'type': 'live_signal',
        'conversationId': 5,
        'senderId': 2,
        'senderDeviceId': 4,
        'ciphertext': sealed,
      });
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50)); // AES-GCM is async
      expect(container.read(liveViewProvider(5)).points[10]!.point, const GeoPoint(28.59, 77.34));

      // Sealed with some other key: ignored.
      final forged = await LiveUpdateSealer().seal(LiveUpdateSealer.newKey(), {
        'shareId': 10,
        'lat': 0,
        'lng': 0,
        'at': 3,
      });
      socket.controller.add({
        'type': 'live_signal',
        'conversationId': 5,
        'senderId': 2,
        'senderDeviceId': 4,
        'ciphertext': forged,
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(liveViewProvider(5)).points[10]!.point, const GeoPoint(28.59, 77.34));
    });

    testWidgets('the full map: where it is, and Directions in the phone\'s maps app', (tester) async {
      serverMessages = [
        message(10, location: {'lat': 28.5355, 'lng': 77.391, 'name': 'Sector 18 Market', 'address': 'Noida'}),
      ];
      late ProviderContainer container;
      await tester.runAsync(() async => container = await openContainer());
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LocationScreen(conversationId: 5, messageId: 10)),
        ),
      );
      await tester.pump();
      expect(find.text('Sector 18 Market'), findsWidgets);
      expect(find.text('Noida'), findsOneWidget);
      await tester.tap(find.text('Directions'));
      await tester.pump();
      expect(launched.single.toString(), 'google.navigation:q=28.5355,77.391&mode=d');
      await tester.pumpWidget(const SizedBox());
      // The chat's local database closes on the real clock.
      await tester.runAsync(() async {
        container.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
    });
  });
}
