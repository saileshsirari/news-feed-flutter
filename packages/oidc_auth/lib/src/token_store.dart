import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'token_set.dart';

/// Where tokens are kept between app launches.
abstract interface class TokenStore {
  Future<TokenSet?> read();
  Future<void> write(TokenSet tokens);
  Future<void> clear();
}

/// The platform's secure storage: the Keychain on iOS, encrypted
/// preferences with a Keystore key on Android, WebCrypto-encrypted local
/// storage on the web (the weakest of the three: a script injected into the
/// page could still read it).
class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage, this.key = 'oidc_auth.tokens'})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final String key;

  @override
  Future<TokenSet?> read() async {
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    try {
      return TokenSet.decode(raw);
    } on Object {
      await clear(); // Unreadable (an older format): as if signed out.
      return null;
    }
  }

  @override
  Future<void> write(TokenSet tokens) => _storage.write(key: key, value: tokens.encode());

  @override
  Future<void> clear() => _storage.delete(key: key);
}

/// Keeps tokens only while the app runs; for tests.
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this.tokens]);

  TokenSet? tokens;

  @override
  Future<TokenSet?> read() async => tokens;

  @override
  Future<void> write(TokenSet tokens) async => this.tokens = tokens;

  @override
  Future<void> clear() async => tokens = null;
}
