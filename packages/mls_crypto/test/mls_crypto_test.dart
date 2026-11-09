import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mls_crypto/mls_crypto.dart';

void main() {
  setUpAll(initMlsCrypto);

  final group = utf8.encode('conversation:5');

  test('two devices exchange an encrypted message through the bridge', () async {
    final alice = await MlsDevice.newInstance(identity: utf8.encode('alice'));
    final bob = await MlsDevice.newInstance(identity: utf8.encode('bob'));

    await alice.createGroup(groupId: group);
    final invitation = await alice.addMember(groupId: group, keyPackage: await bob.keyPackage());
    expect(await bob.join(welcome: invitation.welcome), group);

    final ciphertext = await alice.encrypt(groupId: group, plaintext: utf8.encode('hi bob 👋'));
    expect(utf8.decode(ciphertext, allowMalformed: true), isNot(contains('hi bob')));

    final received = await bob.receive(groupId: group, message: ciphertext);
    expect(utf8.decode(received.sender!), 'alice');
    expect(utf8.decode(received.plaintext!), 'hi bob 👋');
  });

  test('the self-test passes on this platform', () async {
    expect(await mlsSelfTest(), startsWith('OK'));
  });

  test('a Rust error arrives as an MlsError, not a crash', () async {
    final alice = await MlsDevice.newInstance(identity: utf8.encode('alice'));
    await expectLater(alice.join(welcome: [1, 2, 3]), throwsA(isA<MlsError>()));
  });
}
