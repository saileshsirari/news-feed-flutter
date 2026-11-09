//! Encrypting a photo or video before it's uploaded, the way Signal and
//! WhatsApp do: each file gets its own random key, the server only ever
//! stores the encrypted bytes, and the key travels inside the (MLS
//! encrypted) chat message, so only the chat's members can open the file.

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};

use super::device::MlsError;

/// Marks a sealed file (and is authenticated with it): "MLF1", then the
/// 12-byte nonce, then the AES-256-GCM ciphertext and tag.
const FILE_FORMAT: &[u8; 4] = b"MLF1";
const HEADER: usize = 4 + 12;

/// A file sealed under a key of its own.
pub struct SealedFile {
    /// 32 random bytes; send it only inside an encrypted message.
    pub key: Vec<u8>,
    /// What gets uploaded.
    pub ciphertext: Vec<u8>,
}

fn random<const N: usize>() -> Result<[u8; N], MlsError> {
    let mut bytes = [0u8; N];
    getrandom::getrandom(&mut bytes).map_err(|e| MlsError(format!("randomness: {e:?}")))?;
    Ok(bytes)
}

/// Encrypts [plaintext] under a fresh random key. Any change to the
/// result makes [open_file] fail, so a swapped or damaged file is caught.
pub fn seal_file(plaintext: Vec<u8>) -> Result<SealedFile, MlsError> {
    let key = random::<32>()?;
    let nonce = random::<12>()?;
    let cipher = Aes256Gcm::new_from_slice(&key).map_err(|e| MlsError(format!("file key: {e:?}")))?;
    let sealed = cipher
        .encrypt(Nonce::from_slice(&nonce), Payload { msg: &plaintext, aad: FILE_FORMAT })
        .map_err(|_| MlsError("couldn't encrypt the file".into()))?;
    let mut ciphertext = Vec::with_capacity(HEADER + sealed.len());
    ciphertext.extend_from_slice(FILE_FORMAT);
    ciphertext.extend_from_slice(&nonce);
    ciphertext.extend_from_slice(&sealed);
    Ok(SealedFile { key: key.to_vec(), ciphertext })
}

/// The file [seal_file] sealed; an error if [key] is wrong or the bytes
/// were changed.
pub fn open_file(key: Vec<u8>, ciphertext: Vec<u8>) -> Result<Vec<u8>, MlsError> {
    if key.len() != 32 {
        return Err(MlsError("a file key must be 32 bytes".into()));
    }
    if ciphertext.len() < HEADER || &ciphertext[..4] != FILE_FORMAT {
        return Err(MlsError("not a sealed file".into()));
    }
    let cipher = Aes256Gcm::new_from_slice(&key).map_err(|e| MlsError(format!("file key: {e:?}")))?;
    cipher
        .decrypt(Nonce::from_slice(&ciphertext[4..HEADER]), Payload { msg: &ciphertext[HEADER..], aad: FILE_FORMAT })
        .map_err(|_| MlsError("the file couldn't be decrypted (wrong key, or changed)".into()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_sealed_file_opens_only_with_its_own_key_and_unchanged() {
        let photo = b"pretend this is a JPEG".to_vec();
        let sealed = seal_file(photo.clone()).unwrap();
        assert_ne!(sealed.ciphertext[HEADER..], photo[..]);
        assert_eq!(open_file(sealed.key.clone(), sealed.ciphertext.clone()).unwrap(), photo);

        // Same file again: a different key and different bytes.
        let again = seal_file(photo.clone()).unwrap();
        assert_ne!(again.key, sealed.key);
        assert_ne!(again.ciphertext, sealed.ciphertext);

        // Another file's key, or one flipped bit, and it won't open.
        assert!(open_file(again.key.clone(), sealed.ciphertext.clone()).is_err());
        let mut tampered = sealed.ciphertext.clone();
        *tampered.last_mut().unwrap() ^= 1;
        assert!(open_file(sealed.key.clone(), tampered).is_err());
        assert!(open_file(sealed.key, b"MLF1short".to_vec()).is_err());
    }
}
