import 'dart:typed_data';

/// One device's end-to-end encryption state: its own keys (they never
/// leave the native or WebAssembly side) and the MLS groups it's in, one
/// per encrypted conversation. Bytes in, bytes out.
abstract interface class MlsDevice {
  /// The identity this device registered with (e.g. "user:42/device:7").
  Future<Uint8List> identity();

  /// Everything this device knows (keys, unused key packages, every group),
  /// sealed with AES-256-GCM under [key] (32 random bytes kept in the
  /// platform's secure storage). Save it after every change.
  Future<Uint8List> snapshot(List<int> key);

  /// A one-time "key package": what someone needs to add this device to a
  /// group. Public; uploaded to the server for others to fetch.
  Future<Uint8List> keyPackage();

  /// Starts an encrypted group with just this device in it.
  Future<void> createGroup(List<int> groupId);

  /// Adds the device behind [keyPackage] to the group: a commit for the
  /// other members, a welcome for the new device.
  Future<MlsInvitation> addMember(List<int> groupId, List<int> keyPackage);

  /// Adds several devices in one step: one commit, one welcome they all join with.
  Future<MlsInvitation> addMembers(List<int> groupId, List<List<int>> keyPackages);

  /// Whether this device is in the group.
  Future<bool> hasGroup(List<int> groupId);

  /// How many changes the group has been through. A change is only valid on
  /// top of the latest one, so the server checks this.
  Future<int> epoch(List<int> groupId);

  /// Joins the group a welcome invites this device to; returns its id.
  Future<Uint8List> join(List<int> welcome);

  /// Encrypts [plaintext] for everyone in the group.
  Future<Uint8List> encrypt(List<int> groupId, List<int> plaintext);

  /// Decrypts a message, or applies a group change from another member.
  Future<MlsReceived> receive(List<int> groupId, List<int> message);

  /// Who's in the group, by the identity each device registered with.
  Future<List<Uint8List>> members(List<int> groupId);
}

/// What adding someone produces.
class MlsInvitation {
  const MlsInvitation({required this.commit, required this.welcome});

  /// For the group's existing members.
  final Uint8List commit;

  /// For the new device.
  final Uint8List welcome;
}

/// What came out of an incoming message: a chat message (its sender and
/// bytes), or, with both null, a group change that's already applied.
class MlsReceived {
  const MlsReceived({this.sender, this.plaintext});

  final Uint8List? sender;
  final Uint8List? plaintext;

  bool get isMessage => plaintext != null;
}

/// A photo or video sealed under a key of its own (see sealFile).
class MlsSealedFile {
  const MlsSealedFile({required this.key, required this.ciphertext});

  /// 32 random bytes; send it only inside an encrypted message.
  final Uint8List key;

  /// What gets uploaded.
  final Uint8List ciphertext;
}

/// Something went wrong in the encryption library (never anything secret).
class MlsException implements Exception {
  const MlsException(this.message);
  final String message;

  @override
  String toString() => 'MlsException: $message';
}
