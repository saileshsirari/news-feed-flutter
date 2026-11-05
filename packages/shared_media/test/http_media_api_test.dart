import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_media/shared_media.dart';

void main() {
  late List<http.Request> requests;

  HttpMediaApi apiReplying(int status, Map<String, dynamic> body) => HttpMediaApi(
        baseUrl: Uri.parse('https://api.test'),
        userId: 7,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode(body), status);
        }),
      );

  setUp(() => requests = []);

  test('requestUpload sends the file details and parses the ticket', () async {
    final api = apiReplying(201, {
      'mediaId': 3,
      'uploadUrl': 'https://bucket.test/put/3',
      'method': 'PUT',
      'headers': {'Content-Type': 'image/jpeg'},
      'expiresAt': 99,
    });

    final ticket = await api.requestUpload(
      PickedMedia(bytes: Uint8List(1200), contentType: 'image/jpeg', width: 800, height: 600),
    );

    expect(requests.single.url.toString(), 'https://api.test/media/uploads');
    expect(jsonDecode(requests.single.body), {
      'userId': 7,
      'contentType': 'image/jpeg',
      'sizeBytes': 1200,
      'width': 800,
      'height': 600,
    });
    expect(ticket.mediaId, 3);
    expect(ticket.uploadUrl, Uri.parse('https://bucket.test/put/3'));
    expect(ticket.headers, {'Content-Type': 'image/jpeg'});
  });

  test('completeUpload returns the ready attachment', () async {
    final api = apiReplying(200, {
      'id': 3,
      'ownerId': 7,
      'kind': 'video',
      'contentType': 'video/mp4',
      'sizeBytes': 5000,
      'width': 1280,
      'height': 720,
      'durationMs': 12000,
      'url': 'https://bucket.test/view/3',
    });

    final media = await api.completeUpload(3);

    expect(requests.single.url.path, '/media/3/complete');
    expect(jsonDecode(requests.single.body), {'userId': 7});
    expect(media.kind, MediaKind.video);
    expect(media.durationMs, 12000);
    expect(media.aspectRatio, closeTo(16 / 9, 0.001));
  });

  test('turns an error response into a MediaApiException with its message', () async {
    final api = apiReplying(400, {'error': 'contentType must be one of ...'});
    await expectLater(
      api.requestUpload(PickedMedia(bytes: Uint8List(1), contentType: 'image/gif')),
      throwsA(isA<MediaApiException>()
          .having((e) => e.statusCode, 'statusCode', 400)
          .having((e) => e.message, 'message', 'contentType must be one of ...')),
    );
  });

  test('a 429 becomes a clear "too many uploads" message', () async {
    final api = apiReplying(429, {'error': 'too many requests', 'action': 'upload', 'retryAfterSeconds': 120});
    await expectLater(
      api.requestUpload(PickedMedia(bytes: Uint8List(1), contentType: 'image/jpeg')),
      throwsA(isA<MediaApiException>()
          .having((e) => e.statusCode, 'statusCode', 429)
          .having((e) => e.message, 'message', 'Too many uploads for now. Try again in 120 s.')),
    );
  });
}
