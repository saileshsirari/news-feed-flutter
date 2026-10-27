import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../feed/feed_view_model.dart';
import '../models/models.dart';
import '../network/api_client.dart';
import 'contacts_screen.dart';
import 'conversations_view_model.dart';
import 'conversation_screen.dart';

/// The "Chat" tab itself — your existing conversations, most recent first.
/// Starting something new (a 1:1 or a group) happens on a separate screen
/// (ContactsScreen, reached via the pencil action) rather than here, the same
/// split most chat apps use between "your chats" and "who to message."
class ConversationsListScreen extends StatelessWidget {
  const ConversationsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final feedVm = context.read<FeedViewModel>();
    return ChangeNotifierProvider(
      create: (_) => ConversationsViewModel(
        context.read<ApiClient>(),
        currentUserId: feedVm.currentUserId!,
        socket: feedVm.socket,
      ),
      child: const _ConversationsListView(),
    );
  }
}

class _ConversationsListView extends StatelessWidget {
  const _ConversationsListView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConversationsViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'New chat',
            onPressed: () async {
              // pushReplacement, not push: ContactsScreen's own flows
              // navigate onward into a ConversationScreen once you pick
              // someone (or finish a group) — replacing this route means a
              // single "back" from there returns straight here, instead of
              // through an empty picker screen in between.
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ContactsScreen(currentUserId: vm.currentUserId)),
              );
              vm.load();
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: vm.load),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (vm.isLoading && vm.conversations.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (vm.error != null) {
            return Center(child: Text(vm.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)));
          }
          if (vm.conversations.isEmpty) {
            return const Center(child: Text('No chats yet — tap the pencil to start one.'));
          }
          return ListView.separated(
            itemCount: vm.conversations.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _ConversationRow(vm.conversations[index]),
          );
        },
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  final ConversationSummary conversation;
  const _ConversationRow(this.conversation);

  @override
  Widget build(BuildContext context) {
    final title = conversation.displayTitle();
    return ListTile(
      leading: CircleAvatar(
        child: Icon(conversation.isGroup ? Icons.group : Icons.person),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: conversation.lastMessageBody != null
          ? Text(conversation.lastMessageBody!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : const Text('No messages yet'),
      trailing: conversation.unreadCount > 0
          ? CircleAvatar(
              radius: 12,
              child: Text('${conversation.unreadCount}', style: Theme.of(context).textTheme.labelSmall),
            )
          : null,
      onTap: () async {
        // Await the push and reload on return: the push events this list
        // listens for (see ConversationsViewModel) exclude whoever caused
        // them, so sending a message or marking this conversation read
        // yourself never arrives as a push here — only popping back and
        // re-fetching picks up your own last message / cleared unread count.
        final vm = context.read<ConversationsViewModel>();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ConversationScreen(conversationId: conversation.id, title: title),
          ),
        );
        vm.load();
      },
    );
  }
}
