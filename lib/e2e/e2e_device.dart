import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:chat_store/chat_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mls_crypto/mls_crypto.dart';

import '../chat/local/local_chat.dart';
import '../data/services/api_service.dart';
import '../data/services/service_providers.dart';

/// Where the 32-byte key that seals a user's encryption state is kept: the
/// platform's secure storage (Keychain on iOS, Keystore-backed on Android,
/// WebCrypto-wrapped in the browser). Swappable for tests.
abstract interface class E2eSecrets {
  Future<Uint8List?> read(int userId);
  Future<void> write(int userId, Uint8List key);
}

class SecureStorageSecrets implements E2eSecrets {
  SecureStorageSecrets([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;

  static String _name(int userId) => 'e2e_state_key_user_$userId';

  @override
  Future<Uint8List?> read(int userId) async {
    final value = await _storage.read(key: _name(userId));
    return value == null ? null : base64Decode(value);
  }

  @override
  Future<void> write(int userId, Uint8List key) => _storage.write(key: _name(userId), value: base64Encode(key));
}

/// This install's end-to-end encryption identity for one signed-in user:
/// created once, sealed and saved after every change (a device that loses
/// its state loses its encrypted chats), and with enough one-time key
/// packages on the server for others to add it to encrypted chats.
///
/// Only for signed-in accounts with a registered device: test accounts
/// can't have encryption keys.
class E2eDevice {
  E2eDevice({
    required this.userId,
    required this.store,
    required this.secrets,
    required this.api,
    Future<MlsDevice> Function(List<int> identity)? create,
    Future<MlsDevice> Function(List<int> sealed, List<int> key)? restore,
    Random? random,
  })  : _create = create ?? createMlsDevice,
        _restore = restore ?? restoreMlsDevice,
        _random = random ?? Random.secure();

  final int userId;
  final MessageStore store;
  final E2eSecrets secrets;
  final ApiService api;
  final Future<MlsDevice> Function(List<int> identity) _create;
  final Future<MlsDevice> Function(List<int> sealed, List<int> key) _restore;
  final Random _random;

  /// Top up below this many packages on the server, back up to [batch].
  static const lowWater = 20;
  static const batch = 50;

  static const _stateName = 'e2e_state';
  static const _uploadedName = 'e2e_packages_uploaded';

  MlsDevice? _device;
  Uint8List? _key;
  Future<void> _queue = Future.value();

  /// Runs [work] after any earlier work, so saves never interleave.
  Future<T> _serially<T>(Future<T> Function() work) {
    final result = _queue.then((_) => work());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// This device's MLS state: restored, or created on first use.
  Future<MlsDevice> device(int deviceId) => _serially(() => _load(deviceId));

  Future<MlsDevice> _load(int deviceId) async {
    final existing = _device;
    if (existing != null) return existing;
    final sealed = await store.blob(_stateName);
    final key = await secrets.read(userId);
    if (sealed != null && key != null) {
      try {
        _key = key;
        return _device = await _restore(sealed, key);
      } on MlsException catch (e) {
        // Unreadable (e.g. the secure storage was reset): start over as a
        // new identity; its old packages get replaced on the next upload.
        debugPrint('[e2e] saved state unusable, starting a new identity: $e');
      }
    }
    final freshKey = Uint8List.fromList(List.generate(32, (_) => _random.nextInt(256)));
    await secrets.write(userId, freshKey);
    _key = freshKey;
    final device = await _create(utf8.encode('user:$userId/device:$deviceId'));
    _device = device;
    await store.putBlob(_uploadedName, Uint8List(0)); // not yet: see ensureKeyPackages
    await _save();
    return device;
  }

  Future<void> _save() async => store.putBlob(_stateName, await _device!.snapshot(_key!));

  /// Seals and saves the current state; call after anything changed it.
  Future<void> save() => _serially(_save);

  /// Makes sure the server has enough of this device's key packages. New
  /// packages are saved before they're uploaded: a package whose private
  /// half was lost would only make someone's attempt to add this device fail.
  Future<void> ensureKeyPackages(int deviceId) => _serially(() async {
        final device = await _load(deviceId);
        // Not yet uploaded for this identity: replace whatever an older
        // identity on this install left on the server.
        final firstUpload = (await store.blob(_uploadedName))?.isNotEmpty != true;
        final have = firstUpload ? 0 : await api.keyPackageCount(deviceId);
        if (have >= lowWater) return;
        final packages = [for (var i = have; i < batch; i++) await device.keyPackage()];
        await _save();
        await api.uploadKeyPackages(deviceId, packages, replace: firstUpload);
        if (firstUpload) await store.putBlob(_uploadedName, Uint8List.fromList([1]));
      });
}

/// The signed-in user's encryption device (one per user on this install).
final e2eDeviceProvider = Provider.family<E2eDevice, int>(
  (ref, userId) => E2eDevice(
    userId: userId,
    store: ref.watch(messageStoreProvider(userId)),
    secrets: SecureStorageSecrets(),
    api: ref.watch(apiServiceProvider),
  ),
);
