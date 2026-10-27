import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../call/call_screen.dart';
import '../feed/feed_view_model.dart';
import '../network/api_client.dart';
import '../models/models.dart';
import 'conversation_view_model.dart';

class ConversationScreen extends StatelessWidget {
  final int conversationId;
  final String title;

  const ConversationScreen({super.key, required this.conversationId, required this.title});

  @override
  Widget build(BuildContext context) {
    final feedVm = context.read<FeedViewModel>();
    return ChangeNotifierProvider(
      create: (_) => ConversationViewModel(
        context.read<ApiClient>(),
        conversationId: conversationId,
        currentUserId: feedVm.currentUserId!,
        socket: feedVm.socket,
      ),
      child: _ConversationView(title: title, currentUserId: feedVm.currentUserId!),
    );
  }
}

class _ConversationView extends StatefulWidget {
  final String title;
  final int currentUserId;
  const _ConversationView({required this.title, required this.currentUserId});

  @override
  State<_ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<_ConversationView> {
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
    final vm = context.watch<ConversationViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            tooltip: 'Start call',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CallScreen(conversationId: vm.conversationId, title: widget.title),
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
                      final isMine = message.senderId == widget.currentUserId;
                      // Only the current user's most recent message can show
                      // a "Seen" tick — same single-indicator convention as
                      // WhatsApp, rather than a tick per message.
                      final isLastOfMine = isMine && index == vm.messages.lastIndexWhere((m) => m.senderId == widget.currentUserId);
                      return _MessageBubble(
                        message: message,
                        isMine: isMine,
                        showSeen: isLastOfMine && vm.isReadByOthers(message.id),
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
                      onSubmitted: (_) => _send(vm),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: vm.isSending ? null : () => _send(vm),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _send(ConversationViewModel vm) {
    if (_controller.text.trim().isEmpty) return;
    vm.send(_controller.text);
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
