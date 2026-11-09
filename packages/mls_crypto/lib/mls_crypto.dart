/// End-to-end encryption for chats: MLS (RFC 9420) through OpenMLS, in Rust.
///
/// Call [initMlsCrypto] once at start-up, then use [MlsDevice]: one per
/// app install, holding that device's keys (they never leave Rust). Bytes
/// in, bytes out: key packages (public), welcomes and commits (group
/// changes), and encrypted messages (what the server stores and forwards).
library;

import 'src/rust/frb_generated.dart';

export 'src/rust/api/device.dart' show Invitation, MlsDevice, MlsError, Received;

/// Loads the Rust library. Once, before anything else here.
Future<void> initMlsCrypto() => RustLib.init();
