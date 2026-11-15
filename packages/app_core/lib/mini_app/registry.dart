import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/apps_config.dart';
import 'mini_app.dart';

/// Every mini-app compiled into this build, in Home-grid order. Empty here;
/// each main.dart fills it in (see lib/mini_apps.dart):
///
///     ProviderScope(overrides: [miniAppSlotsProvider.overrideWithValue(slots)], ...)
///
/// Android comparison: the list of feature modules in settings.gradle.
final miniAppSlotsProvider = Provider<List<MiniAppSlot>>((ref) => const []);

/// The ones to show: compiled in AND switched on by the server. Both
/// matter: an app built without taxi can't show it whatever the server
/// says, and the server can close one without an app update.
final launcherSlotsProvider = FutureProvider<List<MiniAppSlot>>((ref) async {
  final slots = ref.watch(miniAppSlotsProvider);
  final config = await ref.watch(appsConfigProvider.future);
  return [
    for (final slot in slots)
      if (config.isEnabled(slot.info.id)) slot,
  ];
});

/// The compiled-in mini-app with [id], or null.
MiniAppSlot? slotFor(List<MiniAppSlot> slots, String id) {
  for (final slot in slots) {
    if (slot.info.id == id) return slot;
  }
  return null;
}

/// Mini-apps whose code is in memory: the ones the sign-in hooks reach
/// (only global, eagerly loaded ones have hooks that matter at sign-in).
List<MiniApp> loadedMiniApps(Ref ref) => [
  for (final slot in ref.read(miniAppSlotsProvider))
    if (slot.loaded != null) slot.loaded!,
];
