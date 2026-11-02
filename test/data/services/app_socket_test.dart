import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/app_socket.dart';

/// A real local WebSocket server, so these exercise the actual
/// connect / drop / reconnect path rather than a fake.
void main() {
  late HttpServer server;
  late List<WebSocket> serverSockets;

  setUp(() async {
    serverSockets = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async => serverSockets.add(await WebSocketTransformer.upgrade(request)));
  });

  tearDown(() => server.close(force: true));

  AppSocket socketFor() => AppSocket(1, AppConfig(apiBaseUrl: Uri.parse('http://127.0.0.1:${server.port}')));

  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 100 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(condition(), isTrue);
  }

  test('retry delays back off and cap at 30s', () {
    expect([for (var i = 0; i < 7; i++) AppSocket.retryDelay(i).inSeconds], [1, 2, 4, 8, 16, 30, 30]);
  });

  test('delivers JSON events and skips non-JSON', () async {
    final socket = socketFor()..connect();
    final events = <Map<String, dynamic>>[];
    socket.events.listen(events.add);
    await waitFor(() => serverSockets.length == 1);

    serverSockets.single
      ..add('not json')
      ..add(jsonEncode({'type': 'feed_updated'}));
    await waitFor(() => events.isNotEmpty);

    expect(events, [
      {'type': 'feed_updated'},
    ]);
    socket.disconnect();
  });

  test('reconnects after the server drops it, then says so', () async {
    final socket = socketFor()..connect();
    final events = <Map<String, dynamic>>[];
    socket.events.listen(events.add);
    await waitFor(() => serverSockets.length == 1);

    // Like a server restart: the connection just goes away.
    await serverSockets.single.close();

    await waitFor(() => serverSockets.length == 2); // retried after ~1s
    await waitFor(() => events.isNotEmpty);
    expect(events, [
      {'type': 'reconnected'},
    ]);

    // The same events stream keeps working on the new connection.
    serverSockets.last.add(jsonEncode({'type': 'message_created'}));
    await waitFor(() => events.length == 2);
    expect(events.last, {'type': 'message_created'});
    socket.disconnect();
  });

  test('disconnect stops it from reconnecting', () async {
    final socket = socketFor()..connect();
    await waitFor(() => serverSockets.length == 1);

    socket.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    expect(serverSockets, hasLength(1));
  });
}
