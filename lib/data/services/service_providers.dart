import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_config.dart';
import '../../session/user_session.dart';
import 'api_service.dart';

/// The app's stateless services, one each for the whole app (the Riverpod
/// equivalent of Hilt @Singleton @Provides). Tests swap any of them with
/// `ProviderScope(overrides: [apiServiceProvider.overrideWithValue(fake)])`.

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment());

final apiServiceProvider = Provider<ApiService>(
  (ref) => ApiService(ref.watch(appConfigProvider)),
);

final userSessionProvider = Provider<UserSession>((ref) => UserSession());
