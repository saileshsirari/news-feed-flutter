import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_media/shared_media.dart';

/// Not real encryption: "S" + every byte flipped, opened only with [key].
class FakeSealer implements MediaSealer {
  static final key = Uint8List.fromList(List.filled(32, 7));

  @override
  Future<({Uint8List key, Uint8List ciphertext})> seal(Uint8List plaintext) async =>
      (key: key, ciphertext: Uint8List.fromList([83, for (final b in plaintext) b ^ 0xff]));

  @override
  Future<Uint8List> open(Uint8List key, Uint8List ciphertext) async {
    if (key.first != 7 || ciphertext.first != 83) throw StateError('wrong key');
    return Uint8List.fromList([for (final b in ciphertext.skip(1)) b ^ 0xff]);
  }
}

/// What the server and the bucket were given.
class FakeServer implements MediaApi, MediaUploader {
  final requestedSizes = <int>[];
  final bucket = <int, Uint8List>{};
  final completed = <int>[];
  var _nextId = 500;

  @override
  Future<UploadTicket> requestSealedUpload(int sizeBytes) async {
    requestedSizes.add(sizeBytes);
    final id = _nextId++;
    return UploadTicket(mediaId: id, uploadUrl: Uri.parse('https://bucket.test/$id'), method: 'PUT', headers: const {});
  }

  @override
  Future<void> completeSealedUpload(int mediaId) async => completed.add(mediaId);

  @override
  Future<void> upload(SignedUpload ticket, Uint8List bytes, {void Function(double progress)? onProgress}) async {
    bucket[int.parse(ticket.uploadUrl.pathSegments.last)] = bytes;
    onProgress?.call(1);
  }

  @override
  int get chunkSize => 0;

  @override
  Future<UploadTicket> requestUpload(PickedMedia media) => throw StateError('a readable upload in an encrypted chat');

  @override
  Future<MediaAttachment> completeUpload(int mediaId) => throw StateError('a readable upload in an encrypted chat');
}

Uint8List readLocal(Uri url) => File(url.toFilePath()).readAsBytesSync();

void main() {
  late FakeServer server;
  setUp(() => server = FakeServer());

  final photo = PickedMedia(
    bytes: Uint8List.fromList(utf8.encode('secret photo')),
    contentType: 'image/jpeg',
    width: 4,
    height: 3,
  );

  test('an encrypted upload tells the server only its size, and keeps the photo here', () async {
    final sealed = await MediaUploadService(server, server).uploadSealed(photo, FakeSealer());

    expect(server.requestedSizes, [photo.sizeBytes + 1]); // the sealed size, nothing else
    expect(utf8.decode(server.bucket[sealed.mediaId]!, allowMalformed: true), isNot(contains('secret')));
    expect(server.completed, [sealed.mediaId]);
    expect(sealed.key, FakeSealer.key);
    expect((sealed.kind, sealed.contentType, sealed.width, sealed.height), (MediaKind.image, 'image/jpeg', 4, 3));

    // The sender sees it at once: already on the device, decrypted.
    final container = ProviderContainer.test();
    final opened = await container.read(openedMediaProvider(SealedMediaRequest(sealed, (_) async => null)).future);
    expect(utf8.decode(readLocal(opened.url)), 'secret photo');
  });

  test('someone else\'s device downloads it, decrypts it, and keeps it', () async {
    final sent = await MediaUploadService(server, server).uploadSealed(photo, FakeSealer());
    // As it arrives in the encrypted message on another device: nothing kept yet.
    final received = SealedAttachment.fromJson(jsonDecode(jsonEncode(sent.toJson())) as Map<String, dynamic>);
    expect(received.key, sent.key);
    await File(readLocalPath(sent)).delete();

    var downloads = 0;
    final container = ProviderContainer.test(
      overrides: [
        mediaSealerProvider.overrideWithValue(FakeSealer()),
        sealedDownloadClientProvider.overrideWithValue(
          MockClient((request) async {
            downloads++;
            return http.Response.bytes(server.bucket[int.parse(request.url.pathSegments.last)]!, 200);
          }),
        ),
      ],
    );
    Future<Uri?> linkOf(int id) async => Uri.parse('https://bucket.test/$id');

    final opened = await container.read(openedMediaProvider(SealedMediaRequest(received, linkOf)).future);
    expect(utf8.decode(readLocal(opened.url)), 'secret photo');
    expect(opened.kind, MediaKind.image);

    // Later (another screen, or after a restart): from the device, no download.
    final again = await ProviderContainer.test(
      overrides: [
        sealedDownloadClientProvider.overrideWithValue(MockClient((_) async => throw StateError('downloaded twice'))),
      ],
    ).read(openedMediaProvider(SealedMediaRequest(received, linkOf)).future);
    expect(again.url, opened.url);
    expect(downloads, 1);
  });

  test('a file that was swapped or damaged on the server doesn\'t open', () async {
    final sent = await MediaUploadService(server, server).uploadSealed(photo, FakeSealer());
    await File(readLocalPath(sent)).delete();
    final container = ProviderContainer.test(
      overrides: [
        mediaSealerProvider.overrideWithValue(FakeSealer()),
        sealedDownloadClientProvider.overrideWithValue(MockClient((_) async => http.Response('not it', 200))),
      ],
    );
    await expectLater(
      container.read(openedMediaProvider(SealedMediaRequest(sent, (id) async => Uri.parse('https://x/$id'))).future),
      throwsA(isA<StateError>()),
    );
  });

  test('a draft in an encrypted chat seals every file and gives what the message needs', () async {
    final container = ProviderContainer.test(
      overrides: [
        mediaApiProvider.overrideWithValue(server),
        mediaUploaderProvider.overrideWithValue(server),
        mediaSealerProvider.overrideWithValue(FakeSealer()),
      ],
    );
    const key = (id: 'chat:6:0', maxItems: 10, sealed: true);
    final sub = container.listen(mediaDraftProvider(key), (_, _) {});
    container.read(mediaDraftProvider(key).notifier)
      ..add(photo)
      ..add(PickedMedia(bytes: Uint8List(5), contentType: 'image/png'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    for (var i = 0; i < 20 && sub.read().sealedAttachments == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final sealed = sub.read().sealedAttachments!;
    expect(sub.read().mediaIds, [for (final s in sealed) s.mediaId]);
    expect(sealed.map((s) => s.contentType), ['image/jpeg', 'image/png']);
    expect(server.bucket.keys, unorderedEquals(sub.read().mediaIds!));
  });
}

String readLocalPath(SealedAttachment a) =>
    '${Directory.systemTemp.path}/e2e_media/media-${a.mediaId}.${a.contentType.split('/').last}';
