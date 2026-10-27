import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/api_service.dart';

void main() {
  final config = AppConfig(apiBaseUrl: Uri.parse('https://example.test'));

  /// An ApiService whose HTTP client records the request and replies with [body].
  (ApiService, List<http.Request>) serviceReplying(Object body, {int status = 200}) {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode(body), status);
    });
    return (ApiService(config, httpClient: client), requests);
  }

  test('getFeed builds the same URL as before, including the cursor', () async {
    final (api, requests) = serviceReplying({'posts': [], 'nextCursor': null});

    await api.getFeed(7, limit: 20, cursor: 'abc');

    expect(requests.single.method, 'GET');
    expect(requests.single.url.toString(), 'https://example.test/feed/7?limit=20&cursor=abc');
  });

  test('error status codes become ApiException', () async {
    final (api, _) = serviceReplying({'error': 'not found'}, status: 404);

    expect(
      () => api.getUserByUsername('nobody'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
    );
  });

  test('createPost sends JSON with the author and body', () async {
    final (api, requests) = serviceReplying({'post': null, 'fanoutMs': 0});

    try {
      await api.createPost(authorId: 3, body: 'hello');
    } catch (_) {
      // The fake reply is not a full CreatePostResponse; only the request matters here.
    }

    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/posts');
    expect(jsonDecode(requests.single.body), {'authorId': 3, 'body': 'hello'});
  });

  group('AppConfig.webSocketUri', () {
    test('https becomes wss', () {
      expect(config.webSocketUri(userId: 5).toString(), 'wss://example.test/ws?userId=5');
    });

    test('http becomes ws and keeps the port', () {
      final local = AppConfig(apiBaseUrl: Uri.parse('http://10.0.2.2:3000'));
      expect(local.webSocketUri(userId: 5).toString(), 'ws://10.0.2.2:3000/ws?userId=5');
    });
  });
}
