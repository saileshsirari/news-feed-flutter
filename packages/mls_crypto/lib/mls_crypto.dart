/// End-to-end encryption for chats: MLS (RFC 9420) through OpenMLS, in Rust.
///
/// Call [initMlsCrypto] once at start-up, then use [MlsDevice]: one per
/// app install, holding that device's keys (they never leave Rust). Bytes
/// in, bytes out: key packages (public), welcomes and commits (group
/// changes), and encrypted messages (what the server stores and forwards).
library;

import 'dart:convert';

import 'src/rust/api/device.dart';
import 'src/rust/frb_generated.dart';

export 'src/rust/api/device.dart' show Invitation, MlsDevice, MlsError, Received;

/// Loads the Rust library. Once, before anything else here.
Future<void> initMlsCrypto() => RustLib.init();

/// Two throwaway devices exchange an encrypted message: "OK (…)" if this
/// platform's build works, or what went wrong. For debug builds and checks.
Future<String> mlsSelfTest() async {
  final watch = Stopwatch()..start();
  try {
    final group = utf8.encode('self-test');
    final alice = await MlsDevice.newInstance(identity: utf8.encode('alice'));
    final bob = await MlsDevice.newInstance(identity: utf8.encode('bob'));
    await alice.createGroup(groupId: group);
    final invitation = await alice.addMember(groupId: group, keyPackage: await bob.keyPackage());
    await bob.join(welcome: invitation.welcome);
    final ciphertext = await alice.encrypt(groupId: group, plaintext: utf8.encode('hello'));
    final received = await bob.receive(groupId: group, message: ciphertext);
    final ok = received.plaintext != null && utf8.decode(received.plaintext!) == 'hello';
    return ok ? 'OK (${watch.elapsedMilliseconds} ms)' : 'FAILED: wrong text';
  } on Object catch (e) {
    return 'FAILED: $e';
  }
}
