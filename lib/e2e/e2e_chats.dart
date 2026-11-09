import 'dart:convert';
import 'dart:math';

import 'package:chat_store/chat_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mls_crypto/mls_crypto.dart';

import '../chat/local/local_chat.dart';
import '../data/services/api_service.dart';
import '../data/services/service_providers.dart';
import '../models/models.dart';
import '../session/device_registration.dart';
import 'e2e_device.dart';

/// Why encryption couldn't be turned on, in words for the user.
class E2eUnavailable implements Exception {
  const E2eUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// End-to-end encrypted chats on this device: turning encryption on,
/// joining chats others turned it on in, and reading and sending encrypted
/// messages.
///
/// Two MLS rules shape all of it: each message decrypts exactly once (its
/// key is deleted after use), and each change to a group must be applied
/// in order. So every encrypted chat is processed strictly in order from
/// where this device joined, keeping its place (a cursor per chat), saving
/// the device's state after every step, and storing each decrypted text at
/// once, never to be overwritten.
class E2eChats {
  E2eChats({
    required this.userId,
    required this.api,
    required this.store,
    required this.e2eDevice,
    required this.deviceIdOf,
    Random? random,
  }) : _random = random ?? Random.secure();

  final int userId;
  final ApiService api;
  final MessageStore store;
  final E2eDevice e2eDevice;

  /// This install's device id for the user (null: a test account, or not
  /// registered yet; then encrypted chats can't be read or sent to here).
  final Future<int?> Function() deviceIdOf;
  final Random _random;

  Future<void> _queue = Future.value();

  /// One thing at a time: the device's state and each chat's place must
  /// never be changed by two steps at once.
  Future<T> _serially<T>(Future<T> Function() work) {
    final result = _queue.then((_) => work());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  static String _cursorName(int conversationId) => 'e2e_cursor_$conversationId';
  static String _groupName(int conversationId) => 'e2e_group_$conversationId';

  Future<int?> _cursor(int conversationId) async {
    final bytes = await store.blob(_cursorName(conversationId));
    return bytes == null ? null : int.parse(utf8.decode(bytes));
  }

  Future<void> _setCursor(int conversationId, int seq) =>
      store.putBlob(_cursorName(conversationId), utf8.encode('$seq'));

  Future<String?> _groupId(int conversationId) async {
    final bytes = await store.blob(_groupName(conversationId));
    return bytes == null ? null : utf8.decode(bytes);
  }

  Future<int> _requireDevice() async {
    final deviceId = await deviceIdOf();
    if (deviceId == null) {
      throw const E2eUnavailable('Encrypted chats need a signed-in account on this device (not a test account).');
    }
    return deviceId;
  }

  /// Whether this device can read [conversationId] (it's in the group).
  Future<bool> canRead(int conversationId) async => await _cursor(conversationId) != null;

  /// Turns [conversation] end-to-end encrypted, for good: a group with every
  /// device of every member in it (yours too).
  Future<void> turnOn(ConversationSummary conversation, List<int> memberIds) => _serially(() async {
    final deviceId = await _requireDevice();
    final device = await e2eDevice.device(deviceId);
    final claimed = await api.claimKeyPackages(memberIds);
    // Our own package for this very device came back too: not needed.
    final others = [
      for (final p in claimed.keyPackages)
        if (p.deviceId != deviceId) p,
    ];
    if (!others.any((p) => p.userId != userId)) {
      throw const E2eUnavailable('The other person hasn\'t signed in on a device that supports encryption yet.');
    }
    final groupId = 'conv:${conversation.id}:${_randomHex(8)}';
    final groupBytes = utf8.encode(groupId);
    await device.createGroup(groupBytes);
    final invitation = await device.addMembers(groupBytes, [for (final p in others) p.keyPackage]);
    final epoch = await device.epoch(groupBytes);
    await e2eDevice.save();
    final seq = await api.turnOnE2e(
      conversation.id,
      deviceId: deviceId,
      groupId: groupId,
      epoch: epoch,
      welcome: invitation.welcome,
      recipients: [for (final p in others) (userId: p.userId, deviceId: p.deviceId)],
    );
    await store.putBlob(_groupName(conversation.id), utf8.encode(groupId));
    // Read from the notice on (it's readable, and shows here at once).
    await _setCursor(conversation.id, seq - 1);
    if (claimed.missing.isNotEmpty) {
      debugPrint('[e2e] ${claimed.missing.length} device(s) had no key packages and weren\'t added');
    }
  });

  /// Joins every encrypted chat this device has been added to.
  Future<void> joinWelcomes() => _serially(() async {
    final deviceId = await deviceIdOf();
    if (deviceId == null) return;
    final device = await e2eDevice.device(deviceId);
    for (final w in await api.e2eWelcomes(deviceId)) {
      try {
        if (await _cursor(w.conversationId) == null) {
          await device.join(w.welcome);
          await e2eDevice.save();
          await store.putBlob(_groupName(w.conversationId), utf8.encode(w.groupId));
          // From the notice on: everything after it was sent to this device's group.
          await _setCursor(w.conversationId, w.afterSeq - 1);
        }
      } on MlsException catch (e) {
        // Not for this identity any more (e.g. after a reinstall): drop it.
        debugPrint('[e2e] couldn\'t join chat ${w.conversationId}: $e');
      }
      await api.doneWithWelcome(deviceId, w.id);
    }
  });

  /// Reads [conversationId] forward from this device's place: each message
  /// decrypted once and its text stored, each group change applied, in
  /// order. Your own device's messages are skipped (their text was stored
  /// when sent); your other devices' are read like anyone's.
  Future<void> sync(int conversationId) => _serially(() => _sync(conversationId));

  Future<void> _sync(int conversationId) async {
    final deviceId = await deviceIdOf();
    var cursor = await _cursor(conversationId);
    final groupId = await _groupId(conversationId);
    if (deviceId == null || cursor == null || groupId == null) return;
    final device = await e2eDevice.device(deviceId);
    final group = utf8.encode(groupId);
    while (true) {
      final page = await api.getMessagesBySeq(conversationId, null, afterSeq: cursor, limit: 100);
      if (page.messages.isEmpty) break;
      final stored = <RemoteMessage>[];
      for (final json in page.messages) {
        final decrypted = await _read(device, group, deviceId, json);
        if (decrypted != null) stored.add(decrypted);
      }
      await e2eDevice.save(); // keys moved on: save before anything else
      await store.upsertAll(stored);
      final first = cursor! + 1;
      cursor = page.messages.last['seq'] as int;
      await store.addRange(conversationId, first, cursor);
      await _setCursor(conversationId, cursor);
      if (!page.hasMore) break;
    }
  }

  /// One message from the chat, as this device should store it (null: a
  /// group change, or this device's own message, already stored).
  Future<RemoteMessage?> _read(MlsDevice device, List<int> group, int deviceId, Map<String, dynamic> json) async {
    final mode = json['mode'] as String?;
    if (mode != 'e2e' && mode != 'commit') return remoteMessageFrom(json); // a notice
    if (json['sender_device_id'] == deviceId) return null;
    final ciphertext = base64Decode(json['ciphertext'] as String);
    try {
      final received = await device.receive(group, ciphertext);
      if (!received.isMessage) return null; // a group change, applied
      final payload = jsonDecode(utf8.decode(received.plaintext!)) as Map<String, dynamic>;
      return _decryptedMessage(json, payload['body'] as String? ?? '');
    } on Object catch (e) {
      debugPrint('[e2e] message ${json['id']} couldn\'t be decrypted: $e');
      return _decryptedMessage(json, '🔒 This message couldn\'t be decrypted on this device', failed: true);
    }
  }

  RemoteMessage _decryptedMessage(Map<String, dynamic> json, String body, {bool failed = false}) {
    final message = {...json, 'ciphertext': null, 'body': body, 'decrypted': !failed};
    return RemoteMessage(
      conversationId: json['conversation_id'] as int,
      seq: json['seq'] as int,
      messageId: json['id'] as int,
      body: failed ? '' : body,
      createdAt: json['created_at'] as int,
      json: jsonEncode(message),
    );
  }

  /// Encrypts and sends [text]; stores it here as sent. If the group moved
  /// on meanwhile, catches up and tries once more.
  Future<ChatMessage> send(int conversationId, String text, {required String clientMessageId}) => _serially(() async {
    final deviceId = await _requireDevice();
    final groupId = await _groupId(conversationId);
    if (groupId == null) throw const E2eUnavailable('This device isn\'t in this encrypted chat.');
    final device = await e2eDevice.device(deviceId);
    final group = utf8.encode(groupId);
    for (var attempt = 0; ; attempt++) {
      final ciphertext = await device.encrypt(group, utf8.encode(jsonEncode({'type': 'text', 'body': text})));
      final epoch = await device.epoch(group);
      await e2eDevice.save();
      try {
        final json = await api.sendEncrypted(
          conversationId,
          deviceId: deviceId,
          ciphertext: ciphertext,
          epoch: epoch,
          clientMessageId: clientMessageId,
        );
        final message = _decryptedMessage(json, text);
        await store.upsertAll([message]);
        return ChatMessage.fromJson(jsonDecode(message.json) as Map<String, dynamic>);
      } on ApiException catch (e) {
        if (e.statusCode != 409 || attempt > 0) rethrow;
        await _sync(conversationId); // apply the change we missed, then retry
      }
    }
  });

  String _randomHex(int bytes) =>
      List.generate(bytes, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// The signed-in user's encrypted chats on this install.
final e2eChatsProvider = Provider.family<E2eChats, int>(
  (ref, userId) => E2eChats(
    userId: userId,
    api: ref.watch(apiServiceProvider),
    store: ref.watch(messageStoreProvider(userId)),
    e2eDevice: ref.watch(e2eDeviceProvider(userId)),
    deviceIdOf: () => ref.read(deviceIdsProvider).get(userId),
  ),
);
