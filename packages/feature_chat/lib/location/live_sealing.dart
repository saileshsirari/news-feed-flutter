import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Live positions in an encrypted chat, sealed so only the chat's members
/// can read them, like the photos in it:
///
/// * Starting a live share makes a random 32-byte key, and sends it inside
///   the start message, which MLS encrypts for the chat as usual.
/// * Each position is then sealed with that key (AES-256-GCM: secret, and
///   any tampering is caught) and passed on by the server, which can't
///   read it and doesn't keep it.
///
/// Why not seal each position with MLS itself: every MLS message moves the
/// chat's key ratchet on, and a stream of positions (one every few seconds
/// for hours) would push stored messages too far behind to decrypt. A key
/// of its own, per share, leaves the chat's encryption untouched.
class LiveUpdateSealer {
  LiveUpdateSealer() : _aes = AesGcm.with256bits();

  final AesGcm _aes;

  /// A fresh key for one live share.
  static List<int> newKey() {
    final random = Random.secure();
    return List.generate(32, (_) => random.nextInt(256));
  }

  /// [update] ({shareId, lat, lng, at}) sealed with [key], as base64: a
  /// 12-byte nonce, then the ciphertext and its 16-byte tag.
  Future<String> seal(List<int> key, Map<String, Object?> update) async {
    final box = await _aes.encrypt(utf8.encode(jsonEncode(update)), secretKey: SecretKey(key));
    return base64Encode(box.concatenation());
  }

  /// What [sealed] says, or null if [key] isn't the one it was sealed with
  /// (another share's key), or it was changed.
  Future<Map<String, dynamic>?> open(List<int> key, String sealed) async {
    try {
      final box = SecretBox.fromConcatenation(base64Decode(sealed), nonceLength: 12, macLength: 16);
      final plain = await _aes.decrypt(box, secretKey: SecretKey(key));
      return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    } on Object {
      return null;
    }
  }
}
