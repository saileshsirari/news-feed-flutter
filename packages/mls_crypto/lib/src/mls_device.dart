import 'dart:typed_data';

/// One device's end-to-end encryption state: its own keys (they never
/// leave the native or WebAssembly side) and the MLS groups it's in, one
/// per encrypted conversation. Bytes in, bytes out.
abstract interface class MlsDevice {
  /// A one-time "key package": what someone needs to add this device to a
  /// group. Public; uploaded to the server for others to fetch.
  Future<Uint8List> keyPackage();

  /// Starts an encrypted group with just this device in it.
  Future<void> createGroup(List<int> groupId);

  /// Adds the device behind [keyPackage] to the group: a commit for the
  /// other members, a welcome for the new device.
  Future<MlsInvitation> addMember(List<int> groupId, List<int> keyPackage);

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

/// Something went wrong in the encryption library (never anything secret).
class MlsException implements Exception {
  const MlsException(this.message);
  final String message;

  @override
  String toString() => 'MlsException: $message';
}
