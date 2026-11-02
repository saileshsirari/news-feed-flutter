import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/call/call_notifier.dart';
import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/api_service.dart';
import 'package:news_feed_flutter/data/services/service_providers.dart';
import 'package:news_feed_flutter/session/current_user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// permission_handler's platform channel and its int codes (Permission.camera
// = 1, Permission.microphone = 7; PermissionStatus.denied = 0, granted = 1).
const _permissions = MethodChannel('flutter.baseflow.com/permissions/methods');

// These tests stop before a real LiveKit Room would connect (that needs a
// server); they cover the parts this notifier owns: the join failures and
// the optimistic recording toggle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late bool micGranted;
  late List<http.Request> requests;
  late int recordingStatus;

  setUp(() {
    SharedPreferences.setMockInitialValues({'id': 1, 'username': 'user_1', 'followerCount': 0});
    micGranted = true;
    requests = [];
    recordingStatus = 200;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _permissions,
      (call) async => {7: micGranted ? 1 : 0, 1: 1},
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_permissions, null);
  });

  Future<(ProviderContainer, ProviderSubscription<CallState>)> open() async {
    final api = ApiService(
      AppConfig(apiBaseUrl: Uri.parse('https://example.test')),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/call-token')) return http.Response('no livekit here', 503);
        return http.Response('{}', recordingStatus); // recording start/stop
      }),
    );
    final container = ProviderContainer.test(overrides: [apiServiceProvider.overrideWithValue(api)]);
    await container.read(currentUserProvider.future);
    final sub = container.listen(callProvider(5), (_, _) {});
    return (container, sub);
  }

  test('starts connecting', () async {
    final (_, sub) = await open();

    expect(sub.read().isConnecting, isTrue);
    expect(sub.read().room, isNull);
  });

  test('a denied microphone ends in an error without asking for a call token', () async {
    micGranted = false;
    final (_, sub) = await open();
    await pumpEventQueue();

    expect(sub.read().isConnecting, isFalse);
    expect(sub.read().error, contains('Microphone permission is required'));
    expect(requests, isEmpty);
  });

  test('a failed call token ends in an error', () async {
    final (_, sub) = await open();
    await pumpEventQueue();

    expect(requests.single.url.path, '/conversations/5/call-token');
    expect(sub.read().error, contains('Couldn\'t join call'));
  });

  test('toggleRecording shows recording right away, before LiveKit confirms', () async {
    final (container, sub) = await open();
    await pumpEventQueue(); // let the (failing) join attempt finish first
    final notifier = container.read(callProvider(5).notifier);

    final toggling = notifier.toggleRecording();
    expect(sub.read().isTogglingRecording, isTrue);
    await toggling;

    expect(sub.read().isTogglingRecording, isFalse);
    expect(sub.read().isRecording, isTrue);
    expect(requests.last.url.path, '/conversations/5/recording/start');

    await notifier.toggleRecording();
    expect(sub.read().isRecording, isFalse);
    expect(requests.last.url.path, '/conversations/5/recording/stop');
  });

  test('a failed toggle rethrows for the screen to show, and re-enables the button', () async {
    recordingStatus = 500;
    final (container, sub) = await open();

    await expectLater(container.read(callProvider(5).notifier).toggleRecording(), throwsA(anything));

    expect(sub.read().isTogglingRecording, isFalse);
    expect(sub.read().isRecording, isFalse);
  });
}
