import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:oidc_auth/oidc_auth.dart';
import 'package:app_core/config/app_config.dart';
import 'package:app_core/session/user_session.dart';
import 'package:app_core/data/services/api_service.dart';
import 'package:app_core/orgs/org_header_client.dart';
import 'package:app_core/orgs/orgs_controller.dart';

/// The app's stateless services, one each for the whole app. Tests swap any
/// of them with
/// `ProviderScope(overrides: [apiServiceProvider.overrideWithValue(fake)])`.
///
/// Compose/Android equivalent: a Hilt module.
///   - `Provider<T>((ref) => ...)`      ≈ `@Provides @Singleton fun provideT(): T`
///   - `ref.watch(otherProvider)`        ≈ a constructor/@Provides parameter Hilt injects
///   - the object lives in ProviderScope ≈ the SingletonComponent
///   - built on first use (lazy)         ≈ `@Inject lateinit` / `Lazy<T>`
///   - `overrideWithValue(fake)`         ≈ `@TestInstallIn` replacing the module in tests
///
/// One difference: Hilt finds things by type, Riverpod by the provider
/// variable. `ref.watch(apiServiceProvider)`, not "give me an ApiService".

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment());

/// The signed-in user's tokens, or null when sign-in isn't configured
/// (then only test accounts work). Tests override it.
final authSessionProvider = Provider<AuthSession?>((ref) {
  final oidc = ref.watch(appConfigProvider).oidc;
  if (oidc == null) return null;
  return AuthSession(client: OidcClient(oidc), store: SecureTokenStore());
});

/// An HTTP client for the app's own API, for what's about the person rather
/// than one organisation (who am I, my organisations): it adds the access
/// token when someone is signed in. (Uploads to the bucket use their own client.)
final accountHttpClientProvider = Provider<http.Client>((ref) {
  final auth = ref.watch(authSessionProvider);
  return auth == null ? http.Client() : AuthorizedClient(auth.accessToken);
});

/// The client everything else uses: the account's, plus which organisation
/// the app is showing (X-Org). It's rebuilt when the organisation changes,
/// and so is everything built on it: that's how switching reloads the app.
final apiHttpClientProvider = Provider<http.Client>(
  (ref) => OrgHeaderClient(ref.watch(accountHttpClientProvider), ref.watch(currentOrgIdProvider)),
);

final apiServiceProvider = Provider<ApiService>(
  (ref) => ApiService(ref.watch(appConfigProvider), httpClient: ref.watch(apiHttpClientProvider)),
);

/// The API without an organisation, for signing in (GET /me) and the like:
/// switching organisation mustn't sign anyone out and in again.
final accountApiServiceProvider = Provider<ApiService>(
  (ref) => ApiService(ref.watch(appConfigProvider), httpClient: ref.watch(accountHttpClientProvider)),
);

final userSessionProvider = Provider<UserSession>((ref) => UserSession());
