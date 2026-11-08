import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/services/service_providers.dart';
import '../push/push_registration.dart';

/// What the server is told about this install: a name you'd recognise in a
/// device list ("Pixel 8", "Chrome on macOS") and the platform.
typedef DeviceDescription = ({String name, String platform});

/// This install's own random id, made once and kept (logging out doesn't
/// change it: it's still the same phone or browser). Clearing the app's data
/// or the browser's site data makes it a new install, as it should.
class InstallId {
  static const _key = 'install_id';

  Future<String> get() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null) return saved;
    final fresh = _random();
    await prefs.setString(_key, fresh);
    return fresh;
  }

  static String _random() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(32, (_) => chars[random.nextInt(chars.length)]).join();
  }
}

/// Describes this device from the platform's own information.
Future<DeviceDescription> describeThisDevice() async {
  final info = DeviceInfoPlugin();
  if (kIsWeb) {
    final web = await info.webBrowserInfo;
    final browser = switch (web.browserName) {
      BrowserName.chrome => 'Chrome',
      BrowserName.firefox => 'Firefox',
      BrowserName.safari => 'Safari',
      BrowserName.edge => 'Edge',
      BrowserName.opera => 'Opera',
      BrowserName.samsungInternet => 'Samsung Internet',
      _ => 'Browser',
    };
    final os = web.platform?.trim();
    return (name: os == null || os.isEmpty ? browser : '$browser on $os', platform: 'web');
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      final android = await info.androidInfo;
      return (name: '${_capitalised(android.manufacturer)} ${android.model}'.trim(), platform: 'android');
    case TargetPlatform.iOS:
      final ios = await info.iosInfo;
      return (name: ios.modelName.isNotEmpty ? ios.modelName : ios.model, platform: 'ios');
    case TargetPlatform.macOS:
      return (name: (await info.macOsInfo).computerName, platform: 'macos');
    case TargetPlatform.windows:
      return (name: (await info.windowsInfo).computerName, platform: 'windows');
    default:
      return (name: (await info.linuxInfo).name, platform: 'linux');
  }
}

String _capitalised(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

final installIdProvider = Provider<InstallId>((ref) => InstallId());

/// Swapped in tests (the platform plugin doesn't run there).
final deviceDescriptionProvider = Provider<Future<DeviceDescription> Function()>((ref) => describeThisDevice);

/// This install's id on the server, per user (an install is a different
/// device for each account signed in on it). Known once registered.
class DeviceIds {
  static String _key(int userId) => 'device_id_$userId';

  Future<int?> get(int userId) async => (await SharedPreferences.getInstance()).getInt(_key(userId));

  Future<void> save(int userId, int deviceId) async =>
      (await SharedPreferences.getInstance()).setInt(_key(userId), deviceId);
}

final deviceIdsProvider = Provider<DeviceIds>((ref) => DeviceIds());

/// Tells the server about this install after a real sign-in (test accounts
/// can't have devices; the server refuses them). Each install will hold its
/// own encryption keys and push token, which is why the server needs to know
/// devices, not just users. Best effort: a failure here never blocks login,
/// and the next app start tries again. Then refreshes this device's push
/// address, if notifications are on.
final deviceRegistrarProvider = Provider<Future<void> Function(int userId)>((ref) {
  return (userId) async {
    try {
      final describe = ref.read(deviceDescriptionProvider);
      final installId = await ref.read(installIdProvider).get();
      final device = await describe();
      final deviceId = await ref
          .read(apiServiceProvider)
          .registerDevice(installId, name: device.name, platform: device.platform);
      await ref.read(deviceIdsProvider).save(userId, deviceId);
      await ref.read(pushRegistrationProvider).refresh(userId);
    } on Object catch (e) {
      debugPrint('[devices] registration failed (will retry next start): $e');
    }
  };
});
