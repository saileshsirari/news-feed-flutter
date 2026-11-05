/// Sign-in with an OpenID Connect provider: the authorization code flow
/// with PKCE, token storage, and refresh.
///
/// Knows nothing about the app (like shared_media): the app supplies an
/// [OidcConfig] and uses [AuthSession] for "sign in", "give me a valid access
/// token", and "sign out", and [AuthorizedClient] to put that token on its
/// HTTP requests.
library;

export 'src/auth_session.dart';
export 'src/authorized_client.dart';
export 'src/browser_login.dart';
export 'src/oidc_client.dart';
export 'src/oidc_config.dart';
export 'src/pkce.dart';
export 'src/token_set.dart';
export 'src/token_store.dart';
