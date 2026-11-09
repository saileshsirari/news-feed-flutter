# mls_crypto

End-to-end encryption for chats: MLS (RFC 9420) through OpenMLS, in Rust,
callable from Dart via flutter_rust_bridge. Bytes in, bytes out; a device's
keys never leave Rust. Knows nothing about the app.

- Rust API: `rust/src/api/device.rs` (Rust tests: `cd rust && cargo test`).
- Dart API: `lib/mls_crypto.dart` (generated bindings in `lib/src/rust/`).
- After changing the Rust API: `flutter_rust_bridge_codegen generate`.
- Dart tests load the macOS library from `rust/target/release`, so build it
  first: `cd rust && cargo build --release && cd .. && flutter test`.
- In the app, the build hook (`hook/build.dart`) compiles the crate for the
  target platform during a normal `flutter build` / `flutter run`.
