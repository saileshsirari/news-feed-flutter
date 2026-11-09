//! End-to-end encryption for chats, using MLS (RFC 9420) through OpenMLS.
//!
//! Deliberately small: the app sees bytes in and bytes out, never OpenMLS
//! types. Everything secret stays inside [api::MlsDevice] (in Rust memory);
//! what crosses to Dart is either public (key packages) or ciphertext, plus
//! the plaintext the user is meant to read.
//!
//! Never our own crypto: all of it is OpenMLS and its RustCrypto provider.
pub mod api;
mod frb_generated;
