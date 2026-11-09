use std::collections::HashMap;

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use openmls::prelude::{tls_codec::*, *};
use openmls_basic_credential::SignatureKeyPair;
use openmls_rust_crypto::OpenMlsRustCrypto;
use openmls_traits::OpenMlsProvider;

/// One suite for every group: X25519 key exchange, AES-128-GCM, SHA-256,
/// Ed25519 signatures. MLS's mandatory-to-implement suite, so any other
/// MLS client can talk to us.
const CIPHERSUITE: Ciphersuite = Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;

/// Something went wrong; the message says what (never anything secret).
#[derive(Debug)]
pub struct MlsError(pub String);

impl std::fmt::Display for MlsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for MlsError {}

fn err(context: &str, e: impl std::fmt::Debug) -> MlsError {
    MlsError(format!("{context}: {e:?}"))
}

/// What adding someone to a group produces: a commit for the members who
/// are already in it, and a welcome for the newcomer.
pub struct Invitation {
    pub commit: Vec<u8>,
    pub welcome: Vec<u8>,
}

/// What came out of an incoming MLS message: a chat message (who sent it,
/// and the bytes they sent), or, with both empty, a change to the group
/// (someone added or removed, keys updated) that's already been applied
/// and has nothing to show.
pub struct Received {
    pub sender: Option<Vec<u8>>,
    pub plaintext: Option<Vec<u8>>,
}

impl Received {
    pub fn is_message(&self) -> bool {
        self.plaintext.is_some()
    }
}

/// One device's encryption state: its identity keys and the MLS groups it's
/// in (one per encrypted conversation). Every phone and browser is its own
/// device with its own keys, as MLS intends.
///
/// Held in memory for now; persisting it across app restarts (an encrypted
/// local store) is the next step.
pub struct MlsDevice {
    provider: OpenMlsRustCrypto,
    identity: Vec<u8>,
    signer: SignatureKeyPair,
    credential: CredentialWithKey,
    groups: HashMap<Vec<u8>, MlsGroup>,
}

/// The saved form of a device: "MLS1", then the identity, the signing key's
/// public half, the group ids, and every entry of OpenMLS's storage (which
/// holds all keys and group state). Then sealed (see [MlsDevice::snapshot]).
const SNAPSHOT_FORMAT: &[u8; 4] = b"MLS1";
/// Marks a sealed snapshot (and is authenticated with it).
const SEALED_FORMAT: &[u8; 4] = b"MLSS";

fn put_bytes(out: &mut Vec<u8>, bytes: &[u8]) {
    out.extend_from_slice(&(bytes.len() as u32).to_be_bytes());
    out.extend_from_slice(bytes);
}

/// Reads what [put_bytes] wrote.
struct Reader<'a>(&'a [u8]);

impl<'a> Reader<'a> {
    fn take(&mut self, n: usize) -> Result<&'a [u8], MlsError> {
        if self.0.len() < n {
            return Err(MlsError("saved state is cut short".into()));
        }
        let (head, rest) = self.0.split_at(n);
        self.0 = rest;
        Ok(head)
    }

    fn u32(&mut self) -> Result<usize, MlsError> {
        Ok(u32::from_be_bytes(self.take(4)?.try_into().unwrap()) as usize)
    }

    fn bytes(&mut self) -> Result<Vec<u8>, MlsError> {
        let n = self.u32()?;
        Ok(self.take(n)?.to_vec())
    }
}

fn cipher(key: &[u8]) -> Result<Aes256Gcm, MlsError> {
    if key.len() != 32 {
        return Err(MlsError("the state key must be 32 bytes".into()));
    }
    Aes256Gcm::new_from_slice(key).map_err(|e| err("state key", e))
}

impl MlsDevice {
    /// A new device whose credential carries [identity] (e.g. "user:42/device:7").
    pub fn new(identity: Vec<u8>) -> Result<MlsDevice, MlsError> {
        let identity_for_device = identity.clone();
        let provider = OpenMlsRustCrypto::default();
        let signer = SignatureKeyPair::new(CIPHERSUITE.signature_algorithm()).map_err(|e| err("signature keys", e))?;
        signer.store(provider.storage()).map_err(|e| err("storing signature keys", e))?;
        let credential = CredentialWithKey {
            credential: BasicCredential::new(identity).into(),
            signature_key: signer.to_public_vec().into(),
        };
        let identity = identity_for_device;
        Ok(MlsDevice { provider, identity, signer, credential, groups: HashMap::new() })
    }

    /// Everything this device knows (its keys, unused key packages, every
    /// group's state), sealed with AES-256-GCM under [key] (32 random bytes
    /// the app keeps in the platform's secure storage). Save it after every
    /// change: a device that loses it loses its encrypted chats.
    pub fn snapshot(&self, key: Vec<u8>) -> Result<Vec<u8>, MlsError> {
        let mut plain = SNAPSHOT_FORMAT.to_vec();
        put_bytes(&mut plain, &self.identity);
        put_bytes(&mut plain, self.signer.public());
        plain.extend_from_slice(&(self.groups.len() as u32).to_be_bytes());
        for group_id in self.groups.keys() {
            put_bytes(&mut plain, group_id);
        }
        let values = self.provider.storage().values.read().map_err(|_| MlsError("storage is locked".into()))?;
        plain.extend_from_slice(&(values.len() as u32).to_be_bytes());
        for (k, v) in values.iter() {
            put_bytes(&mut plain, k);
            put_bytes(&mut plain, v);
        }
        drop(values);

        let mut nonce = [0u8; 12];
        getrandom::getrandom(&mut nonce).map_err(|e| err("randomness", e))?;
        let sealed = cipher(&key)?
            .encrypt(Nonce::from_slice(&nonce), Payload { msg: &plain, aad: SEALED_FORMAT })
            .map_err(|_| MlsError("couldn't seal the state".into()))?;
        let mut out = SEALED_FORMAT.to_vec();
        out.extend_from_slice(&nonce);
        out.extend_from_slice(&sealed);
        Ok(out)
    }

    /// The device [snapshot] saved. Fails, without revealing anything, if
    /// the key is wrong or the bytes were changed.
    pub fn restore(sealed: Vec<u8>, key: Vec<u8>) -> Result<MlsDevice, MlsError> {
        if sealed.len() < 16 || &sealed[..4] != SEALED_FORMAT {
            return Err(MlsError("not a saved device state".into()));
        }
        let plain = cipher(&key)?
            .decrypt(Nonce::from_slice(&sealed[4..16]), Payload { msg: &sealed[16..], aad: SEALED_FORMAT })
            .map_err(|_| MlsError("wrong key, or the saved state was changed".into()))?;

        let mut r = Reader(&plain);
        if r.take(4)? != SNAPSHOT_FORMAT {
            return Err(MlsError("unknown saved state format".into()));
        }
        let identity = r.bytes()?;
        let public_key = r.bytes()?;
        let group_ids = (0..r.u32()?).map(|_| r.bytes()).collect::<Result<Vec<_>, _>>()?;
        let provider = OpenMlsRustCrypto::default();
        {
            let mut values = provider.storage().values.write().map_err(|_| MlsError("storage is locked".into()))?;
            for _ in 0..r.u32()? {
                let k = r.bytes()?;
                let v = r.bytes()?;
                values.insert(k, v);
            }
        }

        let signer = SignatureKeyPair::read(provider.storage(), &public_key, CIPHERSUITE.signature_algorithm())
            .ok_or_else(|| MlsError("saved state has no signing key".into()))?;
        let credential = CredentialWithKey {
            credential: BasicCredential::new(identity.clone()).into(),
            signature_key: signer.to_public_vec().into(),
        };
        let mut groups = HashMap::new();
        for id in group_ids {
            let group = MlsGroup::load(provider.storage(), &GroupId::from_slice(&id))
                .map_err(|e| err("loading group", e))?
                .ok_or_else(|| MlsError("saved state is missing a group".into()))?;
            groups.insert(id, group);
        }
        Ok(MlsDevice { provider, identity, signer, credential, groups })
    }

    /// The identity this device registered with.
    pub fn identity(&self) -> Vec<u8> {
        self.identity.clone()
    }

    /// A one-time "key package": what someone needs to add this device to a
    /// group. Public; uploaded to the server for others to fetch. Each one
    /// should be used once, so a device keeps a few on the server.
    pub fn key_package(&self) -> Result<Vec<u8>, MlsError> {
        let bundle = KeyPackage::builder()
            .build(CIPHERSUITE, &self.provider, &self.signer, self.credential.clone())
            .map_err(|e| err("key package", e))?;
        MlsMessageOut::from(bundle.key_package().clone()).to_bytes().map_err(|e| err("key package bytes", e))
    }

    /// Starts an encrypted group (a conversation) with just this device in it.
    pub fn create_group(&mut self, group_id: Vec<u8>) -> Result<(), MlsError> {
        let config = MlsGroupCreateConfig::builder().use_ratchet_tree_extension(true).build();
        let group = MlsGroup::new_with_group_id(
            &self.provider,
            &self.signer,
            &config,
            GroupId::from_slice(&group_id),
            self.credential.clone(),
        )
        .map_err(|e| err("creating group", e))?;
        self.groups.insert(group_id, group);
        Ok(())
    }

    /// Adds the device behind [key_package] to the group. The commit goes to
    /// the group's other members, the welcome to the new device.
    pub fn add_member(&mut self, group_id: Vec<u8>, key_package: Vec<u8>) -> Result<Invitation, MlsError> {
        self.add_members(group_id, vec![key_package])
    }

    /// Adds several devices in one step: one commit for the existing
    /// members, and one welcome that every new device can join with.
    pub fn add_members(&mut self, group_id: Vec<u8>, key_packages: Vec<Vec<u8>>) -> Result<Invitation, MlsError> {
        if key_packages.is_empty() {
            return Err(MlsError("no one to add".into()));
        }
        let mut validated = Vec::with_capacity(key_packages.len());
        for bytes in key_packages {
            match MlsMessageIn::tls_deserialize_exact(bytes)
                .map_err(|e| err("reading key package", e))?
                .extract()
            {
                MlsMessageBodyIn::KeyPackage(kp) => validated.push(
                    kp.validate(self.provider.crypto(), ProtocolVersion::Mls10)
                        .map_err(|e| err("key package isn't valid", e))?,
                ),
                _ => return Err(MlsError("not a key package".into())),
            }
        }
        let (provider, signer) = (&self.provider, &self.signer);
        let group = self.groups.get_mut(&group_id).ok_or_else(|| MlsError("not in that group".into()))?;
        let (commit, welcome, _group_info) =
            group.add_members(provider, signer, &validated).map_err(|e| err("adding members", e))?;
        group.merge_pending_commit(provider).map_err(|e| err("applying commit", e))?;
        Ok(Invitation {
            commit: commit.to_bytes().map_err(|e| err("commit bytes", e))?,
            welcome: welcome.to_bytes().map_err(|e| err("welcome bytes", e))?,
        })
    }

    /// Whether this device is in the group.
    pub fn has_group(&self, group_id: Vec<u8>) -> bool {
        self.groups.contains_key(&group_id)
    }

    /// The group's epoch: how many changes it has been through. A change is
    /// only valid on top of the latest one, so the server checks this.
    pub fn epoch(&self, group_id: Vec<u8>) -> Result<u64, MlsError> {
        Ok(self.groups.get(&group_id).ok_or_else(|| MlsError("not in that group".into()))?.epoch().as_u64())
    }

    /// Joins the group a welcome invites this device to; returns its id.
    pub fn join(&mut self, welcome: Vec<u8>) -> Result<Vec<u8>, MlsError> {
        let welcome = match MlsMessageIn::tls_deserialize_exact(welcome)
            .map_err(|e| err("reading welcome", e))?
            .extract()
        {
            MlsMessageBodyIn::Welcome(welcome) => welcome,
            _ => return Err(MlsError("not a welcome".into())),
        };
        let config = MlsGroupJoinConfig::builder().use_ratchet_tree_extension(true).build();
        let group = StagedWelcome::new_from_welcome(&self.provider, &config, welcome, None)
            .map_err(|e| err("welcome", e))?
            .into_group(&self.provider)
            .map_err(|e| err("joining group", e))?;
        let group_id = group.group_id().as_slice().to_vec();
        self.groups.insert(group_id.clone(), group);
        Ok(group_id)
    }

    /// Encrypts [plaintext] for everyone in the group.
    pub fn encrypt(&mut self, group_id: Vec<u8>, plaintext: Vec<u8>) -> Result<Vec<u8>, MlsError> {
        let (provider, signer) = (&self.provider, &self.signer);
        let group = self.groups.get_mut(&group_id).ok_or_else(|| MlsError("not in that group".into()))?;
        group
            .create_message(provider, signer, &plaintext)
            .map_err(|e| err("encrypting", e))?
            .to_bytes()
            .map_err(|e| err("message bytes", e))
    }

    /// Decrypts a message for one of this device's groups, or applies a
    /// group change (commit) from another member.
    pub fn receive(&mut self, group_id: Vec<u8>, message: Vec<u8>) -> Result<Received, MlsError> {
        let protocol_message = MlsMessageIn::tls_deserialize_exact(message)
            .map_err(|e| err("reading message", e))?
            .try_into_protocol_message()
            .map_err(|e| err("not a group message", e))?;
        let provider = &self.provider;
        let group = self.groups.get_mut(&group_id).ok_or_else(|| MlsError("not in that group".into()))?;
        let processed = group.process_message(provider, protocol_message).map_err(|e| err("decrypting", e))?;
        let sender = processed.credential().serialized_content().to_vec();
        match processed.into_content() {
            ProcessedMessageContent::ApplicationMessage(m) => {
                Ok(Received { sender: Some(sender), plaintext: Some(m.into_bytes()) })
            }
            ProcessedMessageContent::StagedCommitMessage(commit) => {
                group.merge_staged_commit(provider, *commit).map_err(|e| err("applying commit", e))?;
                Ok(Received { sender: None, plaintext: None })
            }
            _ => Ok(Received { sender: None, plaintext: None }),
        }
    }

    /// Who's in the group, by the identity each device registered with.
    pub fn members(&mut self, group_id: Vec<u8>) -> Result<Vec<Vec<u8>>, MlsError> {
        Ok(self.group(&group_id)?.members().map(|m| m.credential.serialized_content().to_vec()).collect())
    }

    fn group(&mut self, group_id: &[u8]) -> Result<&mut MlsGroup, MlsError> {
        self.groups.get_mut(group_id).ok_or_else(|| MlsError("not in that group".into()))
    }
}
