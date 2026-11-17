import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_core/config/app_config.dart';
import 'package:app_core/data/services/api_service.dart';
import 'package:app_core/push/push_channel.dart';
import 'package:app_core/push/push_registration.dart';
import 'package:app_core/push/push_setup.dart';
import 'package:app_core/session/device_registration.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A pretend platform: whether notifications are allowed, and what the user
/// answers to the prompt.
class FakeChannel implements PushChannel {
  bool permitted = false;
  bool answer = true;
  int prompts = 0;
  int stops = 0;

  @override
  bool get supported => true;
  @override
  Future<bool> get allowed async => permitted;
  @override
  Future<bool> requestPermission() async {
    prompts++;
    permitted = answer;
    return answer;
  }

  @override
  Future<Map<String, dynamic>?> address(ApiService api) async => {'kind': 'fcm', 'token': 'token-1'};
  @override
  Future<void> stop() async => stops++;
}

void main() {
  late List<String> calls;
  late FakeChannel channel;

  PushRegistration registration() => PushRegistration(
        api: ApiService(
          AppConfig(apiBaseUrl: Uri.parse('https://example.test')),
          httpClient: MockClient((request) async {
            calls.add('${request.method} ${request.url.path} ${request.body}');
            return http.Response('', 204);
          }),
        ),
        deviceIds: DeviceIds(),
        channel: channel,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    channel = FakeChannel();
  });

  test('a test account (no registered device) can\'t turn notifications on', () async {
    expect(await registration().enable(1), PushEnableResult.needsAccount);
    expect(channel.prompts, 0);
  });

  test('turning on asks once, then tells the server where to reach this device', () async {
    await DeviceIds().save(1, 42);
    final push = registration();

    expect(await push.enable(1), PushEnableResult.on);
    expect(channel.prompts, 1);
    expect(calls.single, 'PUT /push/endpoints/42 ${jsonEncode({'kind': 'fcm', 'token': 'token-1'})}');
    expect(await push.isOn(1), isTrue);
    expect(await push.isOn(2), isFalse); // another account on this device
  });

  test('saying no leaves it off', () async {
    await DeviceIds().save(1, 42);
    channel.answer = false;
    final push = registration();
    expect(await push.enable(1), PushEnableResult.denied);
    expect(calls, isEmpty);
    expect(await push.isOn(1), isFalse);
  });

  test('on start, the address is re-sent only while notifications are on', () async {
    await DeviceIds().save(1, 42);
    final push = registration();
    await push.refresh(1);
    expect(calls, isEmpty); // never turned on

    await push.enable(1);
    calls.clear();
    await push.refresh(1);
    expect(calls, hasLength(1));

    channel.permitted = false; // withdrawn in the system settings
    calls.clear();
    await push.refresh(1);
    expect(calls, isEmpty);
    expect(await push.isOn(1), isFalse);
  });

  test('turning off removes the address and stops the channel', () async {
    await DeviceIds().save(1, 42);
    final push = registration();
    await push.enable(1);
    calls.clear();

    await push.disable(1);
    expect(calls.single, startsWith('DELETE /push/endpoints/42'));
    expect(channel.stops, 1);
    expect(await push.isOn(1), isFalse);
  });

  test('signing out stops this device\'s pushes for that account, but keeps their choice', () async {
    await DeviceIds().save(1, 42);
    channel.permitted = true;
    final push = registration();
    await push.enable(1);
    calls.clear();

    await push.unregister(1);
    expect(calls.single, startsWith('DELETE /push/endpoints/42'));
    // Signing back in re-registers it (their "on" is kept).
    expect(await push.isOn(1), isTrue);
    expect(channel.stops, 0); // the device still gets pushes for whoever signs in next
  });

  test('a push for another account than the one signed in here is dropped', () async {
    await setPushRecipient(2008);
    expect(await isForThisDevice({'type': 'message', 'to': '2008'}), isTrue);
    expect(await isForThisDevice({'type': 'message', 'to': '2004'}), isFalse);
    expect(await isForThisDevice({'type': 'message'}), isTrue); // an older server didn't say
    await setPushRecipient(null); // signed out: nothing is for this device
    expect(await isForThisDevice({'type': 'message', 'to': '2008'}), isFalse);
    // routePush hands nothing to the mini-apps.
    expect(await routePush(const [], {'type': 'message', 'to': '2004'}, appOpen: false), isTrue);
  });
}
