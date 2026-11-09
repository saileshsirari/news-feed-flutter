import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Encrypts a file before upload and decrypts it after download, for
/// end-to-end encrypted chats. This package knows no cryptography: an app
/// that has encrypted chats supplies one, e.g.
///
///     mediaSealerProvider.overrideWithValue(MlsMediaSealer())
abstract interface class MediaSealer {
  /// [plaintext] sealed under a fresh key of its own.
  Future<({Uint8List key, Uint8List ciphertext})> seal(Uint8List plaintext);

  /// What [seal] sealed. Throws if [key] is wrong or the bytes were changed.
  Future<Uint8List> open(Uint8List key, Uint8List ciphertext);
}

final mediaSealerProvider = Provider<MediaSealer>(
  (ref) => throw UnimplementedError('Override mediaSealerProvider to send media in encrypted chats'),
);
