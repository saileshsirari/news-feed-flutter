use mls_crypto::api::device::{MlsDevice, Received};

fn device(name: &str) -> MlsDevice {
    MlsDevice::new(name.as_bytes().to_vec()).unwrap()
}

fn read(device: &mut MlsDevice, group: &[u8], message: &[u8]) -> (String, String) {
    match device.receive(group.to_vec(), message.to_vec()).unwrap() {
        Received::Message { sender, plaintext } => {
            (String::from_utf8(sender).unwrap(), String::from_utf8(plaintext).unwrap())
        }
        Received::GroupChanged => panic!("expected a message, got a group change"),
    }
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
    assert!(matches!(alice.receive(GROUP.to_vec(), invitation.commit).unwrap(), Received::GroupChanged));
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
