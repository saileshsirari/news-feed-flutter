import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PKCE (RFC 7636): proves the app that finishes a sign-in is the one that
/// started it.
///
/// Like a coat check: the app keeps the ticket ([verifier]) and hands the
/// provider only a fingerprint of it ([challenge]). Anyone who steals the
/// code from the redirect still can't swap it for tokens without the ticket,
/// which never left the app. Needed because a phone app or web page can't
/// keep a client secret.
class Pkce {
  Pkce._(this.verifier) : challenge = _s256(verifier);

  /// A fresh random pair; one per sign-in attempt.
  factory Pkce.generate([Random? random]) => Pkce._(randomUrlSafe(64, random));

  /// For tests: a pair from a known verifier.
  factory Pkce.fromVerifier(String verifier) => Pkce._(verifier);

  final String verifier;
  final String challenge;
  String get method => 'S256';

  static String _s256(String verifier) =>
      base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
}

const _urlSafe = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/// [length] characters allowed in a PKCE verifier or a `state`, from a
/// secure random source.
String randomUrlSafe(int length, [Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(length, (_) => _urlSafe[r.nextInt(_urlSafe.length)]).join();
}
