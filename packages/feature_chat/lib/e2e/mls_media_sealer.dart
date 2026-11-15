import 'dart:typed_data';

import 'package:mls_crypto/mls_crypto.dart';
import 'package:shared_media/shared_media.dart';

/// Photos and videos in encrypted chats, sealed by the same Rust library as
/// the messages: a fresh AES-256-GCM key per file (see mls_crypto's sealFile).
class MlsMediaSealer implements MediaSealer {
  const MlsMediaSealer();

  @override
  Future<({Uint8List key, Uint8List ciphertext})> seal(Uint8List plaintext) async {
    final sealed = await sealFile(plaintext);
    return (key: sealed.key, ciphertext: sealed.ciphertext);
  }

  @override
  Future<Uint8List> open(Uint8List key, Uint8List ciphertext) => openFile(key, ciphertext);
}
