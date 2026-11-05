import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// Mirrors news-feed-android's UserSession.kt: which test account (seeded
/// user) you're acting as, persisted so you don't have to re-type it after
/// every app restart. Only for development login: a real sign-in keeps its
/// tokens in secure storage instead (oidc_auth's SecureTokenStore), and the
/// server, not this file, says who that is. SharedPreferences' Dart API is async
/// (unlike Android's synchronous SharedPreferences), so unlike the Kotlin
/// version, current() here is a Future.
class CurrentUser {
  final int id;
  final String username;
  final int followerCount;

  CurrentUser({required this.id, required this.username, required this.followerCount});
}

class UserSession {
  static const _keyId = 'id';
  static const _keyUsername = 'username';
  static const _keyFollowerCount = 'followerCount';

  Future<CurrentUser?> current() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_keyId);
    final username = prefs.getString(_keyUsername);
    if (id == null || username == null) return null;
    return CurrentUser(id: id, username: username, followerCount: prefs.getInt(_keyFollowerCount) ?? 0);
  }

  Future<void> save(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyId, user.id);
    await prefs.setString(_keyUsername, user.username);
    await prefs.setInt(_keyFollowerCount, user.followerCount);
  }

  /// Only this session's keys: other settings (like video quality) stay.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [_keyId, _keyUsername, _keyFollowerCount]) {
      await prefs.remove(key);
    }
  }
}
