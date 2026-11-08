import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/services/api_service.dart';
import '../data/services/service_providers.dart';
import '../session/device_registration.dart';
import 'fcm_channel.dart';
import 'push_channel.dart';
import 'web_push_client.dart';

/// What happened when turning notifications on.
enum PushEnableResult {
  on,

  /// The user (or the browser's settings) said no.
  denied,

  /// This platform can't receive pushes (or Firebase isn't set up here).
  unsupported,

  /// Test accounts have no registered device; a real sign-in is needed.
  needsAccount,

  /// The server isn't set up to send this kind of push.
  notConfigured,
  failed,
}

/// Turns push notifications on and off for this device, and keeps the
/// server's copy of where to reach it current (push addresses change: the
/// browser or FCM may rotate them, so it's re-sent on every start).
class PushRegistration {
  PushRegistration({required this.api, required this.deviceIds, required this.channel});

  final ApiService api;
  final DeviceIds deviceIds;
  final PushChannel? channel;

  static String _onKey(int userId) => 'push_on_$userId';

  bool get supported => channel?.supported ?? false;

  /// On for this user here: they turned it on, and the system still allows it.
  Future<bool> isOn(int userId) async {
    final c = channel;
    if (c == null || !c.supported) return false;
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getBool(_onKey(userId)) ?? false) && await c.allowed;
  }

  /// Asks for permission if needed, then tells the server where to push.
  Future<PushEnableResult> enable(int userId) async {
    final c = channel;
    if (c == null || !c.supported) return PushEnableResult.unsupported;
    final deviceId = await deviceIds.get(userId);
    if (deviceId == null) return PushEnableResult.needsAccount;
    if (!await c.allowed && !await c.requestPermission()) return PushEnableResult.denied;
    try {
      final address = await c.address(api);
      if (address == null) return PushEnableResult.notConfigured;
      await api.registerPushEndpoint(deviceId, address);
    } on Object catch (e) {
      debugPrint('[push] turning on failed: $e');
      return PushEnableResult.failed;
    }
    await (await SharedPreferences.getInstance()).setBool(_onKey(userId), true);
    return PushEnableResult.on;
  }

  Future<void> disable(int userId) async {
    await (await SharedPreferences.getInstance()).setBool(_onKey(userId), false);
    final deviceId = await deviceIds.get(userId);
    try {
      if (deviceId != null) await api.deletePushEndpoint(deviceId);
      await channel?.stop();
    } on Object catch (e) {
      debugPrint('[push] turning off failed: $e');
    }
  }

  /// On every start: if notifications are on, re-send this device's address.
  Future<void> refresh(int userId) async {
    if (!await isOn(userId)) return;
    final c = channel!;
    final deviceId = await deviceIds.get(userId);
    if (deviceId == null) return;
    final address = await c.address(api);
    if (address != null) await api.registerPushEndpoint(deviceId, address);
  }
}

/// The channel for this platform; tests override it.
final pushChannelProvider = Provider<PushChannel?>((ref) {
  if (kIsWeb) return WebPushChannel(createWebPushClient());
  if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) {
    return FcmChannel();
  }
  return null;
});

final pushRegistrationProvider = Provider<PushRegistration>(
  (ref) => PushRegistration(
    api: ref.watch(apiServiceProvider),
    deviceIds: ref.watch(deviceIdsProvider),
    channel: ref.watch(pushChannelProvider),
  ),
);
