import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;
import 'package:shared_media/shared_media.dart';
import '../data/services/service_providers.dart';
import '../models/models.dart';
import '../session/current_user_provider.dart';
import 'message_sender.dart';

enum PendingStatus {
  /// Its photos/videos are still compressing or uploading.
  uploading,

  /// Uploaded; the message itself is on its way to the server.
  sending,

  /// An upload or the send failed; see [PendingMessage.error].
  failed,
}

/// A message you've sent that hasn't reached the server yet, because its
/// photos or videos are still uploading. Shown in the chat at once, with
/// their progress, like WhatsApp.
class PendingMessage {
  const PendingMessage({
    required this.clientMessageId,
    required this.body,
    required this.draftKey,
    this.status = PendingStatus.uploading,
    this.error,
  });

  /// Also what makes sending it again safe (see sendWithOneRetry).
  final String clientMessageId;
  final String body;

  /// The composer draft its attachments were picked in, now this message's:
  /// its uploads keep running there, and its state is the progress shown.
  final MediaDraftKey draftKey;
  final PendingStatus status;
  final String? error;

  PendingMessage copyWith({PendingStatus? status, String? error}) => PendingMessage(
        clientMessageId: clientMessageId,
        body: body,
        draftKey: draftKey,
        status: status ?? this.status,
        error: error,
      );
}

class ChatOutboxState {
  const ChatOutboxState({this.pending = const [], this.sent = const []});

  /// In the order they were sent.
  final List<PendingMessage> pending;

  /// Messages that have reached the server, oldest first, for an open
  /// ConversationNotifier to pick up.
  final List<ChatMessage> sent;

  ChatOutboxState copyWith({List<PendingMessage>? pending, List<ChatMessage>? sent}) =>
      ChatOutboxState(pending: pending ?? this.pending, sent: sent ?? this.sent);
}

/// One conversation's outbox: messages with photos or videos, from the tap
/// on Send until the server has them. Tapping Send hands the composer's
/// draft to a [PendingMessage] (the composer starts a fresh one, so you can
/// keep typing and sending text), and this sends it as soon as every file
/// in it is ready.
///
/// Separate from ConversationNotifier (the history) and kept alive while
/// anything is pending, so leaving the chat doesn't cancel an upload.
///
/// Compose/Android: ≈ a WorkManager-backed outbox repository per chat,
/// minus surviving the app being killed.
class ChatOutboxNotifier extends Notifier<ChatOutboxState> {
  ChatOutboxNotifier(this.conversationId);

  final int conversationId;
  late int _userId;
  final _draftSubscriptions = <String, ProviderSubscription<MediaDraftState>>{};
  KeepAliveLink? _keepAlive;

  @override
  ChatOutboxState build() {
    _userId = ref.read(currentUserProvider).requireValue!.id;
    ref.onDispose(() {
      for (final subscription in _draftSubscriptions.values) {
        subscription.close();
      }
    });
    return const ChatOutboxState();
  }

  /// Sends [body] with the attachments in [draftKey] once they're all
  /// uploaded. The composer must stop using [draftKey] after this.
  void send(String body, MediaDraftKey draftKey) {
    final message = PendingMessage(
      clientMessageId: newClientMessageId(_userId),
      body: body.trim(),
      draftKey: draftKey,
    );
    state = state.copyWith(pending: [...state.pending, message]);
    _keepAlive ??= ref.keepAlive();
    // Listening keeps the draft (and its uploads) alive after the composer
    // moves on to a new one.
    _draftSubscriptions[message.clientMessageId] = ref.listen(
      mediaDraftProvider(draftKey),
      (_, draft) => _onDraftChanged(message.clientMessageId, draft),
      fireImmediately: true,
    );
  }

  /// After a failure: uploads the files that failed again, or, if they're
  /// all uploaded, sends the message again (same client id, so never twice).
  void retry(String clientMessageId) {
    final message = _find(clientMessageId);
    if (message == null || message.status != PendingStatus.failed) return;
    final draft = ref.read(mediaDraftProvider(message.draftKey));
    final mediaIds = draft.mediaIds;
    if (mediaIds != null) {
      _post(clientMessageId, mediaIds);
      return;
    }
    _replace(message.copyWith(status: PendingStatus.uploading));
    final drafts = ref.read(mediaDraftProvider(message.draftKey).notifier);
    for (final item in draft.items.where((i) => i.status == DraftItemStatus.failed)) {
      drafts.retry(item.localId);
    }
  }

  /// Gives up on a pending message. Files already uploaded are left for the
  /// server's cleanup of unattached uploads.
  void discard(String clientMessageId) => _remove(clientMessageId);

  void _onDraftChanged(String clientMessageId, MediaDraftState draft) {
    final message = _find(clientMessageId);
    if (message == null || message.status != PendingStatus.uploading) return;
    final mediaIds = draft.mediaIds;
    if (mediaIds != null) {
      _post(clientMessageId, mediaIds);
    } else if (draft.hasFailures && !draft.isPreparing && !draft.isUploading) {
      final reason = draft.items.firstWhere((i) => i.status == DraftItemStatus.failed).error;
      _replace(message.copyWith(status: PendingStatus.failed, error: reason ?? 'Upload failed'));
    }
  }

  Future<void> _post(String clientMessageId, List<int> mediaIds) async {
    final message = _find(clientMessageId);
    if (message == null) return;
    _replace(message.copyWith(status: PendingStatus.sending));
    try {
      final sent = await sendWithOneRetry(
        ref.read(apiServiceProvider),
        conversationId,
        senderId: _userId,
        body: message.body,
        clientMessageId: clientMessageId,
        mediaIds: mediaIds,
      );
      if (!ref.mounted) return;
      _remove(clientMessageId);
      state = state.copyWith(sent: [...state.sent, sent]);
    } catch (_) {
      if (!ref.mounted || _find(clientMessageId) == null) return;
      _replace(message.copyWith(status: PendingStatus.failed, error: 'Couldn\'t send'));
    }
  }

  PendingMessage? _find(String clientMessageId) {
    for (final message in state.pending) {
      if (message.clientMessageId == clientMessageId) return message;
    }
    return null;
  }

  void _replace(PendingMessage message) => state = state.copyWith(pending: [
        for (final m in state.pending) m.clientMessageId == message.clientMessageId ? message : m,
      ]);

  void _remove(String clientMessageId) {
    _draftSubscriptions.remove(clientMessageId)?.close(); // lets its draft go
    state = state.copyWith(pending: [
      for (final m in state.pending)
        if (m.clientMessageId != clientMessageId) m,
    ]);
    if (state.pending.isEmpty) {
      _keepAlive?.close();
      _keepAlive = null;
    }
  }
}

/// autoDispose, but kept alive while anything is pending (see send).
final chatOutboxProvider =
    NotifierProvider.autoDispose.family<ChatOutboxNotifier, ChatOutboxState, int>(ChatOutboxNotifier.new);
