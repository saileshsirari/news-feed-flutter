use mls_crypto::api::device::MlsDevice;

fn device(name: &str) -> MlsDevice {
    MlsDevice::new(name.as_bytes().to_vec()).unwrap()
}

fn read(device: &mut MlsDevice, group: &[u8], message: &[u8]) -> (String, String) {
    let received = device.receive(group.to_vec(), message.to_vec()).unwrap();
    assert!(received.is_message(), "expected a message, got a group change");
    (String::from_utf8(received.sender.unwrap()).unwrap(), String::from_utf8(received.plaintext.unwrap()).unwrap())
}

const GROUP: &[u8] = b"conversation:5";

/// Alice starts an encrypted chat with Bob; they write to each other.
fn alice_and_bob() -> (MlsDevice, MlsDevice) {
    let mut alice = device("alice");
    let mut bob = device("bob");
    alice.create_group(GROUP.to_vec()).unwrap();
    let invitation = alice.add_member(GROUP.to_vec(), bob.key_package().unwrap()).unwrap();
    assert_eq!(bob.join(invitation.welcome).unwrap(), GROUP);
    (alice, bob)
}

#[test]
fn two_devices_exchange_messages_both_ways() {
    let (mut alice, mut bob) = alice_and_bob();

    let ciphertext = alice.encrypt(GROUP.to_vec(), b"hi bob, see you at 6".to_vec()).unwrap();
    // What the server stores and forwards: not the text.
    assert!(!String::from_utf8_lossy(&ciphertext).contains("see you at 6"));
    assert_eq!(read(&mut bob, GROUP, &ciphertext), ("alice".into(), "hi bob, see you at 6".into()));

    let reply = bob.encrypt(GROUP.to_vec(), "👍 see you".as_bytes().to_vec()).unwrap();
    assert_eq!(read(&mut alice, GROUP, &reply), ("bob".into(), "👍 see you".into()));

    // Many messages in a row keep working (keys move forward each time).
    for i in 0..20 {
        let m = alice.encrypt(GROUP.to_vec(), format!("message {i}").into_bytes()).unwrap();
        assert_eq!(read(&mut bob, GROUP, &m).1, format!("message {i}"));
    }
}

#[test]
fn a_third_member_joins_and_everyone_reads_them() {
    let (mut alice, mut bob) = alice_and_bob();
    let mut carol = device("carol");

    // Bob adds Carol: Carol gets a welcome, Alice gets the group change.
    let invitation = bob.add_member(GROUP.to_vec(), carol.key_package().unwrap()).unwrap();
    assert!(!alice.receive(GROUP.to_vec(), invitation.commit).unwrap().is_message()); // a group change
    carol.join(invitation.welcome).unwrap();

    let hello = carol.encrypt(GROUP.to_vec(), b"hello both".to_vec()).unwrap();
    assert_eq!(read(&mut alice, GROUP, &hello), ("carol".into(), "hello both".into()));
    assert_eq!(read(&mut bob, GROUP, &hello), ("carol".into(), "hello both".into()));

    let mut members = alice.members(GROUP.to_vec()).unwrap();
    members.sort();
    assert_eq!(members, vec![b"alice".to_vec(), b"bob".to_vec(), b"carol".to_vec()]);
}

#[test]
fn a_tampered_message_is_rejected() {
    let (mut alice, mut bob) = alice_and_bob();
    let mut ciphertext = alice.encrypt(GROUP.to_vec(), b"pay 10".to_vec()).unwrap();
    let last = ciphertext.len() - 1;
    ciphertext[last] ^= 1; // one bit changed in transit
    assert!(bob.receive(GROUP.to_vec(), ciphertext).is_err());
}

#[test]
fn someone_outside_the_group_cant_read_it() {
    let (mut alice, _bob) = alice_and_bob();
    let mut mallory = device("mallory");
    let ciphertext = alice.encrypt(GROUP.to_vec(), b"secret".to_vec()).unwrap();
    assert!(mallory.receive(GROUP.to_vec(), ciphertext.clone()).is_err()); // not in the group

    // Not even by starting her own group with the same id.
    mallory.create_group(GROUP.to_vec()).unwrap();
    assert!(mallory.receive(GROUP.to_vec(), ciphertext).is_err());
}

#[test]
fn bad_input_is_an_error_not_a_crash() {
    let mut alice = device("alice");
    assert!(alice.add_member(b"nope".to_vec(), b"garbage".to_vec()).is_err());
    assert!(alice.join(b"garbage".to_vec()).is_err());
    assert!(alice.encrypt(b"not-a-group".to_vec(), b"x".to_vec()).is_err());
}

const KEY: [u8; 32] = [7; 32];

#[test]
fn a_saved_device_restored_mid_conversation_keeps_talking() {
    let (mut alice, bob) = alice_and_bob();
    let first = alice.encrypt(GROUP.to_vec(), b"before the restart".to_vec()).unwrap();

    // Bob's app closes: his state is saved, then loaded on the next start.
    let saved = bob.snapshot(KEY.to_vec()).unwrap();
    drop(bob);
    let mut bob = MlsDevice::restore(saved, KEY.to_vec()).unwrap();
    assert_eq!(bob.identity(), b"bob");

    assert_eq!(read(&mut bob, GROUP, &first), ("alice".into(), "before the restart".into()));
    let reply = bob.encrypt(GROUP.to_vec(), b"back again".to_vec()).unwrap();
    assert_eq!(read(&mut alice, GROUP, &reply), ("bob".into(), "back again".into()));
}

#[test]
fn a_key_package_handed_out_before_a_restart_still_works_after() {
    let mut alice = device("alice");
    let carol = device("carol");
    let key_package = carol.key_package().unwrap(); // uploaded to the server
    let mut carol = MlsDevice::restore(carol.snapshot(KEY.to_vec()).unwrap(), KEY.to_vec()).unwrap();

    alice.create_group(GROUP.to_vec()).unwrap();
    let invitation = alice.add_member(GROUP.to_vec(), key_package).unwrap();
    carol.join(invitation.welcome).unwrap();
    let hello = alice.encrypt(GROUP.to_vec(), b"hi carol".to_vec()).unwrap();
    assert_eq!(read(&mut carol, GROUP, &hello).1, "hi carol");
}

#[test]
fn the_saved_state_is_sealed() {
    let (_alice, bob) = alice_and_bob();
    let saved = bob.snapshot(KEY.to_vec()).unwrap();
    // Nothing readable inside, and every save looks different (random nonce).
    assert!(!saved.windows(3).any(|w| w == b"bob"));
    assert_ne!(saved, bob.snapshot(KEY.to_vec()).unwrap());

    assert!(MlsDevice::restore(saved.clone(), [8; 32].to_vec()).is_err()); // wrong key
    let mut changed = saved.clone();
    let middle = changed.len() / 2;
    changed[middle] ^= 1;
    assert!(MlsDevice::restore(changed, KEY.to_vec()).is_err()); // one bit changed
    assert!(MlsDevice::restore(saved, b"short".to_vec()).is_err()); // not a key
    assert!(MlsDevice::restore(b"garbage".to_vec(), KEY.to_vec()).is_err());
}

#[test]
fn several_devices_added_in_one_step_all_join_with_the_same_welcome() {
    let mut alice_phone = device("alice/phone");
    let mut alice_web = device("alice/web");
    let mut bob_phone = device("bob/phone");
    alice_phone.create_group(GROUP.to_vec()).unwrap();
    assert_eq!(alice_phone.epoch(GROUP.to_vec()).unwrap(), 0);

    let invitation = alice_phone
        .add_members(
            GROUP.to_vec(),
            vec![alice_web.key_package().unwrap(), bob_phone.key_package().unwrap()],
        )
        .unwrap();
    assert_eq!(alice_phone.epoch(GROUP.to_vec()).unwrap(), 1);
    alice_web.join(invitation.welcome.clone()).unwrap();
    bob_phone.join(invitation.welcome).unwrap();
    assert!(bob_phone.has_group(GROUP.to_vec()));
    assert_eq!(bob_phone.epoch(GROUP.to_vec()).unwrap(), 1);

    // Alice's other device reads her message (MLS doesn't let the sending
    // device itself decrypt it; it keeps its own copy of the text).
    let hi = alice_phone.encrypt(GROUP.to_vec(), b"hi from my phone".to_vec()).unwrap();
    assert_eq!(read(&mut alice_web, GROUP, &hi).1, "hi from my phone");
    assert_eq!(read(&mut bob_phone, GROUP, &hi).1, "hi from my phone");
    // The sending device gets nothing to show for its own message: the app
    // keeps the text it sent, rather than reading it back.
    assert!(!alice_phone.receive(GROUP.to_vec(), hi.clone()).unwrap().is_message());
    // Each message decrypts once: its key is deleted after use, so the app
    // must store the text the first time.
    assert!(alice_web.receive(GROUP.to_vec(), hi).is_err());
}
