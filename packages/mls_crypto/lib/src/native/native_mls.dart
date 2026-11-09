import 'dart:typed_data';

import '../mls_device.dart';
import '../rust/api/device.dart' as rust;
import '../rust/api/file.dart' as rust_file;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart' show ExternalLibrary;

import '../rust/frb_generated.dart';

/// Phones and desktops: the Rust library through flutter_rust_bridge.
/// [libraryPath] is for tests on a computer, which load the library built
/// in rust/target/release instead of the app's bundled one.
Future<void> initPlatform([String? libraryPath]) =>
    RustLib.init(externalLibrary: libraryPath == null ? null : ExternalLibrary.open(libraryPath));

Future<MlsDevice> createDevice(List<int> identity) async =>
    _NativeDevice(await _guard(() => rust.MlsDevice.newInstance(identity: identity)));

Future<MlsDevice> restoreDevice(List<int> sealed, List<int> key) async =>
    _NativeDevice(await _guard(() => rust.MlsDevice.restore(sealed: sealed, key: key)));

Future<MlsSealedFile> sealFile(List<int> plaintext) => _guard(() async {
      final sealed = await rust_file.sealFile(plaintext: plaintext);
      return MlsSealedFile(key: sealed.key, ciphertext: sealed.ciphertext);
    });

Future<Uint8List> openFile(List<int> key, List<int> ciphertext) =>
    _guard(() => rust_file.openFile(key: key, ciphertext: ciphertext));

Future<T> _guard<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on rust.MlsError catch (e) {
    throw MlsException(e.field0);
  }
}

class _NativeDevice implements MlsDevice {
  _NativeDevice(this._device);
  final rust.MlsDevice _device;

  @override
  Future<Uint8List> identity() => _guard(_device.identity);

  @override
  Future<Uint8List> snapshot(List<int> key) => _guard(() => _device.snapshot(key: key));

  @override
  Future<Uint8List> keyPackage() => _guard(_device.keyPackage);

  @override
  Future<void> createGroup(List<int> groupId) => _guard(() => _device.createGroup(groupId: groupId));

  @override
  Future<MlsInvitation> addMember(List<int> groupId, List<int> keyPackage) => _guard(() async {
        final invitation = await _device.addMember(groupId: groupId, keyPackage: keyPackage);
        return MlsInvitation(commit: invitation.commit, welcome: invitation.welcome);
      });

  @override
  Future<MlsInvitation> addMembers(List<int> groupId, List<List<int>> keyPackages) => _guard(() async {
        final invitation = await _device.addMembers(
          groupId: groupId,
          keyPackages: [for (final p in keyPackages) p is Uint8List ? p : Uint8List.fromList(p)],
        );
        return MlsInvitation(commit: invitation.commit, welcome: invitation.welcome);
      });

  @override
  Future<bool> hasGroup(List<int> groupId) => _guard(() => _device.hasGroup(groupId: groupId));

  @override
  Future<int> epoch(List<int> groupId) => _guard(() async => (await _device.epoch(groupId: groupId)).toInt());

  @override
  Future<Uint8List> join(List<int> welcome) => _guard(() => _device.join(welcome: welcome));

  @override
  Future<Uint8List> encrypt(List<int> groupId, List<int> plaintext) =>
      _guard(() => _device.encrypt(groupId: groupId, plaintext: plaintext));

  @override
  Future<MlsReceived> receive(List<int> groupId, List<int> message) => _guard(() async {
        final received = await _device.receive(groupId: groupId, message: message);
        return MlsReceived(sender: received.sender, plaintext: received.plaintext);
      });

  @override
  Future<List<Uint8List>> members(List<int> groupId) => _guard(() => _device.members(groupId: groupId));
}
