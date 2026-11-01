import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/api_service.dart';
import 'package:news_feed_flutter/data/services/service_providers.dart';
import 'package:news_feed_flutter/data/services/socket_provider.dart';
import 'package:news_feed_flutter/session/current_user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Nothing listens on this port, so the socket's connect attempt fails
  // instantly and harmlessly; these tests only care about its lifecycle.
  final config = AppConfig(apiBaseUrl: Uri.parse('http://127.0.0.1:9'));

  /// A container whose ApiService answers GET /users?username=... with [user]
  /// (or 404 when null) instead of hitting the network.
  ProviderContainer containerReturning(Map<String, dynamic>? user) {
    final api = ApiService(
      config,
      httpClient: MockClient((request) async =>
          user == null ? http.Response('not found', 404) : http.Response(jsonEncode(user), 200)),
    );
    return ProviderContainer.test(overrides: [
      appConfigProvider.overrideWithValue(config),
      apiServiceProvider.overrideWithValue(api),
    ]);
  }

  const celebrity = {'id': 7, 'username': 'celebrity', 'created_at': 0, 'followerCount': 1000};

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts logged out when nothing is saved', () async {
    final container = containerReturning(celebrity);

    expect(await container.read(currentUserProvider.future), isNull);
  });

  test('login sets the user and saves the session for the next app start', () async {
    final container = containerReturning(celebrity);
    await container.read(currentUserProvider.future);

    await container.read(currentUserProvider.notifier).login('celebrity');

    final user = container.read(currentUserProvider).value!;
    expect((user.id, user.username, user.followerCount), (7, 'celebrity', 1000));

    // A fresh container is a fresh app start: it reads the saved session.
    final restarted = containerReturning(celebrity);
    expect((await restarted.read(currentUserProvider.future))?.id, 7);
  });

  test('a failed login throws and stays logged out', () async {
    final container = containerReturning(null);
    await container.read(currentUserProvider.future);

    await expectLater(container.read(currentUserProvider.notifier).login('nobody'), throwsA(anything));

    expect(container.read(currentUserProvider).value, isNull);
  });

  test('logout clears the user and the saved session', () async {
    final container = containerReturning(celebrity);
    await container.read(currentUserProvider.future);
    await container.read(currentUserProvider.notifier).login('celebrity');

    await container.read(currentUserProvider.notifier).logout();

    expect(container.read(currentUserProvider).value, isNull);
    expect(await containerReturning(celebrity).read(currentUserProvider.future), isNull);
  });

  test('every listener of a user gets the same socket, until nobody listens', () async {
    final container = containerReturning(celebrity);

    final a = container.listen(socketProvider(7), (_, _) {});
    final b = container.listen(socketProvider(7), (_, _) {});
    expect(a.read(), same(b.read()));
    expect(a.read().userId, 7);

    final first = a.read();
    a.close();
    b.close();
    await container.pump(); // let autoDispose run

    // Disposed (and disconnected) once the last listener left, so the next
    // listener gets a brand-new connection.
    final c = container.listen(socketProvider(7), (_, _) {});
    expect(c.read(), isNot(same(first)));
  });
}
