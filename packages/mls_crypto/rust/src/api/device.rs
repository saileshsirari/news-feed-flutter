use std::collections::HashMap;

use openmls::prelude::{tls_codec::*, *};
use openmls_basic_credential::SignatureKeyPair;
use openmls_rust_crypto::OpenMlsRustCrypto;

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
    signer: SignatureKeyPair,
    credential: CredentialWithKey,
    groups: HashMap<Vec<u8>, MlsGroup>,
}

impl MlsDevice {
    /// A new device whose credential carries [identity] (e.g. "user:42/device:7").
    pub fn new(identity: Vec<u8>) -> Result<MlsDevice, MlsError> {
        let provider = OpenMlsRustCrypto::default();
        let signer = SignatureKeyPair::new(CIPHERSUITE.signature_algorithm()).map_err(|e| err("signature keys", e))?;
        signer.store(provider.storage()).map_err(|e| err("storing signature keys", e))?;
        let credential = CredentialWithKey {
            credential: BasicCredential::new(identity).into(),
            signature_key: signer.to_public_vec().into(),
        };
        Ok(MlsDevice { provider, signer, credential, groups: HashMap::new() })
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
        let key_package = match MlsMessageIn::tls_deserialize_exact(key_package)
            .map_err(|e| err("reading key package", e))?
            .extract()
        {
            MlsMessageBodyIn::KeyPackage(kp) => kp
                .validate(self.provider.crypto(), ProtocolVersion::Mls10)
                .map_err(|e| err("key package isn't valid", e))?,
            _ => return Err(MlsError("not a key package".into())),
        };
        let (provider, signer) = (&self.provider, &self.signer);
        let group = self.groups.get_mut(&group_id).ok_or_else(|| MlsError("not in that group".into()))?;
        let (commit, welcome, _group_info) = group
            .add_members(provider, signer, core::slice::from_ref(&key_package))
            .map_err(|e| err("adding member", e))?;
        group.merge_pending_commit(provider).map_err(|e| err("applying commit", e))?;
        Ok(Invitation {
            commit: commit.to_bytes().map_err(|e| err("commit bytes", e))?,
            welcome: welcome.to_bytes().map_err(|e| err("welcome bytes", e))?,
        })
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
