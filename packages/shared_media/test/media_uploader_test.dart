import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_media/shared_media.dart';

void main() {
  final ticket = UploadTicket(
    mediaId: 1,
    uploadUrl: Uri.parse('https://bucket.test/put/1'),
    method: 'PUT',
    headers: const {'Content-Type': 'image/png'},
  );

  test('PUTs the bytes with the ticket headers and reports progress', () async {
    late http.Request sent;
    final uploader = MediaUploader(
      chunkSize: 4,
      httpClient: MockClient((request) async {
        sent = request;
        return http.Response('', 200);
      }),
    );
    final progress = <double>[];

    await uploader.upload(ticket, Uint8List.fromList(List.generate(10, (i) => i)), onProgress: progress.add);

    expect(sent.method, 'PUT');
    expect(sent.url, ticket.uploadUrl);
    expect(sent.headers['Content-Type'], 'image/png');
    expect(sent.bodyBytes, List.generate(10, (i) => i));
    expect(progress, [0.4, 0.8, 1.0]);
  });

  test('throws when the bucket rejects the upload', () async {
    final uploader = MediaUploader(httpClient: MockClient((_) async => http.Response('expired', 403)));
    await expectLater(
      uploader.upload(ticket, Uint8List(3)),
      throwsA(isA<UploadFailedException>().having((e) => e.statusCode, 'statusCode', 403)),
    );
  });

  test('progress follows what a slow connection has actually received', () async {
    // A real socket to a server that reads slowly, so the upload has to
    // wait for it: progress must not run far ahead of what's arrived.
    const total = 48 * 1024 * 1024;
    var received = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final subscription = request.listen(null);
      subscription.onData((chunk) {
        received += chunk.length;
        subscription.pause(Future.delayed(const Duration(milliseconds: 2)));
      });
      await subscription.asFuture<void>();
      request.response.statusCode = 200;
      await request.response.close();
    });

    final aheadBy = <double>[];
    await MediaUploader(httpClient: http.Client()).upload(
      UploadTicket(
        mediaId: 1,
        uploadUrl: Uri.parse('http://127.0.0.1:${server.port}/put'),
        method: 'PUT',
        headers: const {'Content-Type': 'video/mp4'},
      ),
      Uint8List(total),
      onProgress: (p) => aheadBy.add(p - received / total),
    );

    expect(received, total);
    expect(aheadBy.length, greaterThan(100));
    // Socket buffers (a few MB, more under load) let it run somewhat ahead;
    // pushing everything in at once was 100% ahead before anything arrived.
    expect(aheadBy.reduce((a, b) => a > b ? a : b), lessThan(0.6));
  });
}
