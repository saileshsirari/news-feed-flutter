import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../call/call_screen.dart';
import '../session/current_user_provider.dart';
import '../models/models.dart';
import 'conversation_notifier.dart';

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

  const ConversationScreen({super.key, required this.conversationId, required this.title});

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

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

    // Keep the newest message in view: jump there when the thread first
    // loads, glide there when a message arrives or you send one. A side
    // effect, so ref.listen (≈ `LaunchedEffect(messages.size) {
    // listState.animateScrollToItem(last) }` in Compose).
    ref.listen(conversationProvider(widget.conversationId).select((s) => s.messages.length), (previous, next) {
      if (next > (previous ?? 0)) _scrollToBottom(animate: (previous ?? 0) > 0);
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: vm.messages.length,
                    itemBuilder: (context, index) {
                      final message = vm.messages[index];
                      final isMine = message.senderId == currentUserId;
                      // Only the current user's most recent message can show
                      // a "Seen" tick — same single-indicator convention as
                      // WhatsApp, rather than a tick per message.
                      final isLastOfMine = isMine && index == vm.messages.lastIndexWhere((m) => m.senderId == currentUserId);
                      return _MessageBubble(
                        message: message,
                        isMine: isMine,
                        showSeen: isLastOfMine && vm.isReadByOthers(message.id, currentUserId: currentUserId),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(hintText: 'Message', border: OutlineInputBorder()),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: vm.isSending ? null : _send,
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
      final bottom = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(bottom, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      } else {
        _scrollController.jumpTo(bottom);
      }
    });
  }

  void _send() {
    if (_controller.text.trim().isEmpty) return;
    // ref.read(...notifier) to call a method (≈ `vm.send(text)` in Compose);
    // ref.watch above is only for reading state.
    ref.read(conversationProvider(widget.conversationId).notifier).send(_controller.text);
    _controller.clear();
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final bool showSeen;
  const _MessageBubble({required this.message, required this.isMine, this.showSeen = false});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
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
              if (!isMine)
                Text(
                  '@${message.senderUsername}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              Text(message.body),
            ],
          ),
        ),
        if (showSeen)
          Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 4),
            child: Text(
              'Seen',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}
