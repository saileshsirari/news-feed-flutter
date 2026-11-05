import 'browser_login.dart';
import 'oidc_client.dart';
import 'pkce.dart';
import 'token_set.dart';
import 'token_store.dart';

/// The user closed the sign-in page, or it came back with an error.
class SignInCancelledException implements Exception {
  const SignInCancelledException([this.reason]);
  final String? reason;

  @override
  String toString() => 'Sign-in didn\'t finish${reason == null ? '' : ': $reason'}';
}

/// One signed-in user's tokens, for the life of the app.
///
/// Like a hotel key card: [signIn] is the front desk (shows ID once), the
/// access token is the card (works for a while), and [accessToken] quietly
/// re-encodes it with the refresh token when it's about to stop working.
class AuthSession {
  AuthSession({
    required this.client,
    required this.store,
    this.browser = systemBrowserLogin,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final OidcClient client;
  final TokenStore store;
  /// Shows the sign-in page; the system browser unless a test swaps it.
  final BrowserLogin browser;
  final DateTime Function() _now;

  TokenSet? _tokens;
  bool _loaded = false;
  Future<TokenSet?>? _refreshing;

  /// Whether a sign-in is saved (it may still turn out to be revoked).
  Future<bool> get isSignedIn async => await _current() != null;

  /// Opens the provider's sign-in page; returns once the app has tokens.
  /// Throws [SignInCancelledException] if the user backs out.
  Future<void> signIn() async {
    final pkce = Pkce.generate();
    final state = randomUrlSafe(32);
    final url = await client.authorizationUrl(pkce: pkce, state: state);

    final Uri redirect;
    try {
      redirect = await browser(url, client.config.redirectUri);
    } on Object catch (e) {
      throw SignInCancelledException('$e');
    }

    final params = redirect.queryParameters;
    if (params['error'] != null) {
      throw SignInCancelledException(params['error_description'] ?? params['error']);
    }
    // A redirect we didn't ask for (or a stale one): never use its code.
    if (params['state'] != state) throw const SignInCancelledException('state mismatch');
    final code = params['code'];
    if (code == null) throw const SignInCancelledException('no code in the redirect');

    await _save(await client.exchangeCode(code: code, pkce: pkce));
  }

  /// A usable access token, refreshed first if needed; null when signed out
  /// (never signed in, or the refresh token was revoked).
  ///
  /// Several requests asking at once share one refresh: a refresh token may
  /// be single-use, so two parallel refreshes could sign the user out.
  Future<String?> accessToken() async {
    final tokens = await _current();
    if (tokens == null) return null;
    if (!tokens.needsRefresh(_now())) return tokens.accessToken;
    final refreshed = await (_refreshing ??= _refresh(tokens).whenComplete(() => _refreshing = null));
    return refreshed?.accessToken;
  }

  Future<TokenSet?> _refresh(TokenSet tokens) async {
    try {
      final next = await client.refresh(tokens);
      await _save(next);
      return next;
    } on OidcException catch (e) {
      if (!e.isInvalidGrant) rethrow; // A server hiccup: try again next time.
      await _forget();
      return null;
    }
  }

  /// Forgets the tokens here and asks the provider to revoke the refresh
  /// token, so a copy elsewhere stops working too.
  Future<void> signOut() async {
    final tokens = await _current();
    await _forget();
    final refreshToken = tokens?.refreshToken;
    if (refreshToken != null) await client.revoke(refreshToken);
  }

  Future<TokenSet?> _current() async {
    if (!_loaded) {
      _tokens = await store.read();
      _loaded = true;
    }
    return _tokens;
  }

  Future<void> _save(TokenSet tokens) async {
    _tokens = tokens;
    _loaded = true;
    await store.write(tokens);
  }

  Future<void> _forget() async {
    _tokens = null;
    _loaded = true;
    await store.clear();
  }
}
