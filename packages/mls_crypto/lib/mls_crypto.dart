/// End-to-end encryption for chats: MLS (RFC 9420) through OpenMLS, in Rust.
///
/// Call [initMlsCrypto] once at start-up, then [createMlsDevice]: one per
/// app install, holding that device's keys (they never leave Rust). Bytes
/// in, bytes out: key packages (public), welcomes and commits (group
/// changes), and encrypted messages (what the server stores and forwards).
///
/// On phones and desktops it runs through flutter_rust_bridge; in the
/// browser, the same Rust code as WebAssembly, called directly.
library;

import 'dart:convert';

import 'src/mls_device.dart';
import 'src/native/native_mls.dart' if (dart.library.js_interop) 'src/web/web_mls.dart' as platform;

export 'src/mls_device.dart';

/// Loads the library for this platform. Once, before anything else here.
Future<void> initMlsCrypto() => platform.initPlatform();

/// A new device whose credential carries [identity] (e.g. "user:42/device:7").
Future<MlsDevice> createMlsDevice(List<int> identity) => platform.createDevice(identity);

/// The device [MlsDevice.snapshot] saved; throws [MlsException] if [key] is
/// wrong or the bytes were changed.
Future<MlsDevice> restoreMlsDevice(List<int> sealed, List<int> key) => platform.restoreDevice(sealed, key);

/// Two throwaway devices exchange an encrypted message: "OK (…)" if this
/// platform's build works, or what went wrong. For debug builds and checks.
Future<String> mlsSelfTest() async {
  final watch = Stopwatch()..start();
  try {
    final group = utf8.encode('self-test');
    final alice = await createMlsDevice(utf8.encode('alice'));
    final bob = await createMlsDevice(utf8.encode('bob'));
    await alice.createGroup(group);
    final invitation = await alice.addMember(group, await bob.keyPackage());
    await bob.join(invitation.welcome);
    final ciphertext = await alice.encrypt(group, utf8.encode('hello'));
    final received = await bob.receive(group, ciphertext);
    final ok = received.plaintext != null && utf8.decode(received.plaintext!) == 'hello';
    return ok ? 'OK (${watch.elapsedMilliseconds} ms)' : 'FAILED: wrong text';
  } on Object catch (e) {
    return 'FAILED: $e';
  }
}
