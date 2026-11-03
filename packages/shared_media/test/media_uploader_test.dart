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
}
