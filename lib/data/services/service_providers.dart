import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_config.dart';
import '../../session/user_session.dart';
import 'api_service.dart';

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

final apiServiceProvider = Provider<ApiService>(
  (ref) => ApiService(ref.watch(appConfigProvider)),
);

final userSessionProvider = Provider<UserSession>((ref) => UserSession());
