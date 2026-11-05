import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_media/shared_media.dart';

import '../presence/presence_widgets.dart';
import '../call/call_screen.dart';
import '../session/current_user_provider.dart';
import '../models/models.dart';
import 'chat_outbox.dart';
import 'conversation_notifier.dart';
import 'message_info_sheet.dart';

/// Compose/Android: ≈ a screen composable doing
/// `val state by vm.state.collectAsState()` with
/// `vm = hiltViewModel(key = conversationId)`, plus `remember`ed text field
/// and scroll state (the TextEditingController / ScrollController below).
///
/// No ChangeNotifierProvider wrapper any more: conversationProvider
/// (autoDispose) is created when this screen first watches it and cleared
/// when the screen closes.
class ConversationScreen extends ConsumerStatefulWidget {
  final int conversationId;
  final String title;

  /// The other person in a 1:1, for "online" / "last seen" under the title;
  /// null for a group.
  final int? otherUserId;

  const ConversationScreen({super.key, required this.conversationId, required this.title, this.otherUserId});

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  /// The composer's attachments: a draft of its own, so photos picked in one
  /// chat don't show up in another. Sending hands the draft (and its
  /// uploads) to the outbox, and the composer moves on to a new one.
  int _draftGeneration = 0;
  MediaDraftKey get _draftKey => (id: 'chat:${widget.conversationId}:$_draftGeneration', maxItems: 10);

  @override
  void initState() {
    super.initState();
    // The send button depends on whether there's text.
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserProvider).requireValue!.id;
    // Was: context.watch<ConversationViewModel>(). Same idea: read the
    // state and rebuild whenever the notifier assigns a new one.
    final vm = ref.watch(conversationProvider(widget.conversationId));
    final outbox = ref.watch(chatOutboxProvider(widget.conversationId));
    // Watching also keeps the draft alive while this chat is open.
    final draft = ref.watch(mediaDraftProvider(_draftKey));
    // Attachments don't have to be uploaded yet (the outbox waits for them),
    // but one that failed (too big, too long) has to be fixed or removed.
    final hasText = _controller.text.trim().isNotEmpty;
    final canSend = !draft.hasFailures && (draft.isEmpty ? hasText && !vm.isSending : true);

    // Keep the newest message in view when one arrives or you send one. The
    // list is reversed (newest at the bottom, offset 0), so older messages
    // loading in at the top never move what you're reading, and "the bottom"
    // is just offset 0.
    ref.listen(conversationProvider(widget.conversationId).select((s) => s.messages.lastOrNull?.id), (previous, next) {
      if (next != null && next != previous) _scrollToBottom(animate: previous != null);
    });
    ref.listen(chatOutboxProvider(widget.conversationId).select((s) => s.pending.length), (previous, next) {
      if (next > (previous ?? 0)) _scrollToBottom(animate: true);
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title),
            if (widget.otherUserId != null) PresenceSubtitle(userId: widget.otherUserId!),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            tooltip: 'Start call',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CallScreen(conversationId: widget.conversationId, title: widget.title),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (vm.error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(vm.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: vm.isLoading
                ? const Center(child: CircularProgressIndicator())
                : NotificationListener<ScrollNotification>(
                    // Near the top (the end of a reversed list): load older.
                    onNotification: (notification) {
                      final position = notification.metrics;
                      if (position.extentAfter < 400) {
                        ref.read(conversationProvider(widget.conversationId).notifier).loadOlder();
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(8),
                      // From the bottom: yours still uploading, then sent
                      // messages newest first, then a spinner at the top
                      // while older ones load.
                      itemCount: outbox.pending.length + vm.messages.length + (vm.isLoadingOlder ? 1 : 0),
                      itemBuilder: (context, index) {
                        final pendingCount = outbox.pending.length;
                        if (index < pendingCount) {
                          return _PendingBubble(
                            conversationId: widget.conversationId,
                            message: outbox.pending[pendingCount - 1 - index],
                          );
                        }
                        final fromNewest = index - pendingCount;
                        if (fromNewest >= vm.messages.length) {
                          return const Padding(
                            padding: EdgeInsets.all(12),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final messageIndex = vm.messages.length - 1 - fromNewest;
                        final message = vm.messages[messageIndex];
                        final isMine = message.senderId == currentUserId;
                        // Every message of yours shows how far it got (✓, ✓✓,
                        // blue ✓✓); long-press for who has read it.
                        return _MessageBubble(
                          message: message,
                          isMine: isMine,
                          tick: isMine ? vm.tickFor(message.id, currentUserId: currentUserId) : null,
                          onLongPress: isMine ? () => showMessageInfo(context, message, vm, currentUserId) : null,
                        );
                      },
                    ),
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!draft.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ComposerAttachments(draftKey: _draftKey),
                    ),
                  Row(
                    children: [
                      AddMediaButton(draftKey: _draftKey),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: const InputDecoration(hintText: 'Message', border: OutlineInputBorder()),
                          onSubmitted: (_) => canSend ? _send(draft) : null,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        tooltip: 'Send',
                        onPressed: canSend ? () => _send(draft) : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// After the frame, so the list has laid out the new message and
  /// maxScrollExtent includes it.
  void _scrollToBottom({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      // Reversed list: the bottom is offset 0.
      if (animate) {
        _scrollController.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      } else {
        _scrollController.jumpTo(0);
      }
    });
  }

  /// Text goes straight out. With attachments, the message goes to the
  /// outbox, which sends it once its uploads finish (like WhatsApp): the
  /// composer is free again at once, for more text or more photos.
  void _send(MediaDraftState draft) {
    // ref.read(...notifier) to call a method (≈ `vm.send(text)` in Compose);
    // ref.watch above is only for reading state.
    if (draft.isEmpty) {
      ref.read(conversationProvider(widget.conversationId).notifier).send(_controller.text);
    } else {
      ref.read(chatOutboxProvider(widget.conversationId).notifier).send(_controller.text, _draftKey);
      setState(() => _draftGeneration++);
    }
    _controller.clear();
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;

  /// How far it got (your messages only).
  final MessageTick? tick;
  final VoidCallback? onLongPress;
  const _MessageBubble({required this.message, required this.isMine, this.tick, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final time = TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(message.createdAt)).format(context);
    return Column(
      crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onLongPress: onLongPress,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            decoration: BoxDecoration(
              color: isMine ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMine) Text('@${message.senderUsername}', style: Theme.of(context).textTheme.labelSmall),
                if (message.media.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    // Tapping a video plays it full screen (MediaGrid's default).
                    child: MediaGrid(media: message.media),
                  ),
                if (message.body.isNotEmpty) Text(message.body),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        time,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      if (tick != null) Padding(padding: const EdgeInsets.only(left: 4), child: TickIcon(tick!)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A message of yours whose photos/videos are still uploading: shown in the
/// chat at once with their progress, faded until the server has it, with
/// retry or discard if something failed.
class _PendingBubble extends ConsumerWidget {
  const _PendingBubble({required this.conversationId, required this.message});

  final int conversationId;
  final PendingMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final outbox = ref.read(chatOutboxProvider(conversationId).notifier);
    final failed = message.status == PendingStatus.failed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Opacity(
          opacity: failed ? 1 : 0.85,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(8),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            decoration: BoxDecoration(color: colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PendingMediaGrid(draftKey: message.draftKey),
                if (message.body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(message.body)),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 4),
          child: failed
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        message.error ?? 'Couldn\'t send',
                        style: textTheme.labelSmall?.copyWith(color: colorScheme.error),
                      ),
                    ),
                    TextButton(onPressed: () => outbox.retry(message.clientMessageId), child: const Text('Retry')),
                    TextButton(onPressed: () => outbox.discard(message.clientMessageId), child: const Text('Discard')),
                  ],
                )
              : Text(
                  message.status == PendingStatus.sending ? '🕓 Sending…' : '🕓 Uploading…',
                  style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
        ),
      ],
    );
  }
}
