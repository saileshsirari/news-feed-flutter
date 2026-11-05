import 'package:shared_media/shared_media.dart';

import '../../session/current_user_provider.dart';
import 'service_providers.dart';

/// Plugs this app into the shared_media package: which server to upload
/// through, and as which user (with the signed-in user's token). The package knows nothing about the app
/// otherwise, so a split-out chat app would supply its own version of this.
///
/// Only read while someone is logged in (from a composer), so the user is
/// always there.
final mediaOverrides = [
  mediaApiProvider.overrideWith(
    (ref) => HttpMediaApi(
      baseUrl: ref.watch(appConfigProvider).apiBaseUrl,
      userId: ref.watch(currentUserProvider).requireValue!.id,
      httpClient: ref.watch(apiHttpClientProvider),
    ),
  ),
];
