import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mls_crypto/mls_crypto.dart';

void main() {
  setUpAll(initMlsCrypto);

  final group = utf8.encode('conversation:5');

  test('two devices exchange an encrypted message through the bridge', () async {
    final alice = await createMlsDevice(utf8.encode('alice'));
    final bob = await createMlsDevice(utf8.encode('bob'));

    await alice.createGroup(group);
    final invitation = await alice.addMember(group, await bob.keyPackage());
    expect(await bob.join(invitation.welcome), group);

    final ciphertext = await alice.encrypt(group, utf8.encode('hi bob 👋'));
    expect(utf8.decode(ciphertext, allowMalformed: true), isNot(contains('hi bob')));

    final received = await bob.receive(group, ciphertext);
    expect(received.isMessage, isTrue);
    expect(utf8.decode(received.sender!), 'alice');
    expect(utf8.decode(received.plaintext!), 'hi bob 👋');
    expect((await alice.members(group)).map(utf8.decode).toSet(), {'alice', 'bob'});
  });

  test('a device saved and restored carries on in its chats', () async {
    final key = List<int>.filled(32, 9);
    final alice = await createMlsDevice(utf8.encode('alice'));
    var bob = await createMlsDevice(utf8.encode('bob'));
    await alice.createGroup(group);
    await bob.join((await alice.addMember(group, await bob.keyPackage())).welcome);

    bob = await restoreMlsDevice(await bob.snapshot(key), key);
    expect(utf8.decode(await bob.identity()), 'bob');
    final received = await bob.receive(group, await alice.encrypt(group, utf8.encode('still here?')));
    expect(utf8.decode(received.plaintext!), 'still here?');

    await expectLater(restoreMlsDevice(await bob.snapshot(key), List.filled(32, 1)), throwsA(isA<MlsException>()));
  });

  test('several devices added in one step join with one welcome', () async {
    final alicePhone = await createMlsDevice(utf8.encode('alice/phone'));
    final aliceWeb = await createMlsDevice(utf8.encode('alice/web'));
    final bob = await createMlsDevice(utf8.encode('bob'));
    await alicePhone.createGroup(group);
    expect(await alicePhone.epoch(group), 0);
    final invitation = await alicePhone.addMembers(group, [await aliceWeb.keyPackage(), await bob.keyPackage()]);
    expect(await alicePhone.epoch(group), 1);
    await aliceWeb.join(invitation.welcome);
    await bob.join(invitation.welcome);
    expect(await bob.hasGroup(group), isTrue);
    expect(await bob.hasGroup(utf8.encode('other')), isFalse);
    final hi = await alicePhone.encrypt(group, utf8.encode('hi all'));
    expect(utf8.decode((await bob.receive(group, hi)).plaintext!), 'hi all');
    expect(utf8.decode((await aliceWeb.receive(group, hi)).plaintext!), 'hi all');
  });

  test('the self-test passes on this platform', () async {
    expect(await mlsSelfTest(), startsWith('OK'));
  });

  test('a Rust error arrives as an MlsException, not a crash', () async {
    final alice = await createMlsDevice(utf8.encode('alice'));
    await expectLater(alice.join([1, 2, 3]), throwsA(isA<MlsException>()));
  });
}
