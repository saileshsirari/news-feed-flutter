/// Chat as a mini-app: conversations, end-to-end encryption, calls and
/// presence. The shell knows it only through [ChatMiniApp].
library;

import 'package:app_core/app_core.dart';
import 'package:app_core/data/services/api_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderListenable;
import 'package:mls_crypto/mls_crypto.dart';
import 'package:shared_media/shared_media.dart';

import 'call/call_screen.dart';
import 'chat/chat_shell_listener.dart';
import 'chat/conversation_screen.dart';
import 'chat/conversations_list_screen.dart';
import 'chat/conversations_notifier.dart';
import 'chat/local/local_chat.dart';
import 'chat_info.dart';
import 'e2e/e2e_device.dart';
import 'e2e/mls_media_sealer.dart';

export 'chat_info.dart';

/// Chats you have unread messages in: the number on Chat's icon.
final unreadChatsProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(conversationsProvider).conversations.where((c) => c.unreadCount > 0).length,
);

const _messages = NotificationChannel(id: 'messages', name: 'Messages', description: 'New chat messages');

class ChatMiniApp extends MiniApp {
  @override
  MiniAppInfo get info => chatInfo;

  @override
  Widget buildHome(BuildContext context) => const ConversationsListScreen();

  /// `app://chat/conversation/<id>?title=&otherUserId=` and `app://chat/call/<id>?title=`.
  @override
  Widget? screenFor(Uri link) {
    final title = link.queryParameters['title'] ?? 'Chat';
    if (AppLinks.idOf(link, 'conversation') case final id?) {
      return ConversationScreen(
        conversationId: id,
        title: title,
        otherUserId: int.tryParse(link.queryParameters['otherUserId'] ?? ''),
      );
    }
    if (AppLinks.idOf(link, 'call') case final id?) return CallScreen(conversationId: id, title: title);
    return null;
  }

  @override
  ProviderListenable<int> get badgeCount => unreadChatsProvider;

  @override
  Widget wrapSignedIn(Widget child) => ChatShellListener(child: child);

  @override
  List<Override> get overrides => [
    // Encrypted chats' photos and videos: sealed on the device before upload.
    mediaSealerProvider.overrideWithValue(const MlsMediaSealer()),
  ];

  /// The end-to-end encryption library (Rust). A failure to load must
  /// never stop the app.
  @override
  Future<void> initialise() async {
    try {
      await initMlsCrypto();
      // Debug builds only: prove the library works on this device by having
      // two pretend devices exchange an encrypted message. Shows in the log.
      if (kDebugMode) debugPrint('[e2e] self-test: ${await mlsSelfTest()}');
    } on Object catch (e) {
      debugPrint('[e2e] encryption library not available: $e');
    }
  }

  /// End-to-end encryption: this device's keys exist, and others can add
  /// it to encrypted chats (enough key packages on the server).
  @override
  Future<void> onDeviceRegistered(Ref ref, int userId, int deviceId) =>
      ref.read(e2eDeviceProvider(userId)).ensureKeyPackages(deviceId);

  /// This user's chat history leaves the device with them, and their
  /// database closes. It's open whenever someone is signed in (background
  /// sync), so only an open one needs clearing; no point opening one to
  /// empty it.
  @override
  Future<void> onSignOut(Ref ref, int userId) async {
    // (Riverpod 3.5 renames this `ref.read(provider.exists)`; the app is
    // locked to 3.4, which only has this one.)
    // ignore: deprecated_member_use
    if (!ref.exists(chatDatabaseProvider(userId))) return;
    try {
      await ref.read(messageStoreProvider(userId)).clear().timeout(const Duration(seconds: 5));
    } on Object catch (_) {
      // Still close it; the database is per user, so nobody else reads it.
    }
    ref.invalidate(chatDatabaseProvider(userId));
  }

  /// A push about a new message. With the app open the socket has already
  /// delivered it, so nothing to show. Otherwise: the push carries only ids
  /// (Google never sees the text), so fetch the message from our server
  /// with the saved sign-in, and show it.
  @override
  Future<bool> showPush(Map<String, dynamic> data, {required bool appOpen}) async {
    if (data['type'] != 'message') return false;
    if (appOpen) return true;
    final conversationId = int.tryParse('${data['conversationId']}');
    final seq = int.tryParse('${data['seq']}');
    if (conversationId == null || seq == null) return true;

    var title = 'New message';
    var body = 'New message';
    try {
      final message = await _fetchMessage(conversationId, seq);
      if (message != null) {
        title = '@${message['sender_username']}';
        final text = (message['body'] as String? ?? '').trim();
        // End-to-end encrypted: the server's copy has no text. (Decrypting
        // here, in the background, comes later.)
        body = message['mode'] == 'e2e'
            ? '🔒 New message'
            : text.isNotEmpty
            ? text
            : '📷 Photo or video';
      }
    } on Object catch (e) {
      debugPrint('[push] couldn\'t fetch the message, showing a plain notification: $e');
    }
    // One notification per chat: a newer message replaces the older one.
    await showLocalNotification(
      id: conversationId,
      title: title,
      body: body,
      channel: _messages,
      link: AppLinks.conversation(conversationId, title: title),
    );
    return true;
  }

  /// The message with [seq], from our server, signed in as the saved user.
  static Future<Map<String, dynamic>?> _fetchMessage(int conversationId, int seq) async {
    final signIn = await savedSignIn();
    if (signIn == null) return null;
    final api = ApiService(signIn.config, httpClient: signIn.client);
    final page = await api.getMessagesBySeq(conversationId, null, afterSeq: seq - 1, limit: 1);
    return page.messages.isEmpty ? null : page.messages.first;
  }
}
