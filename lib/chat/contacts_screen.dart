import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../network/api_client.dart';
import 'contacts_view_model.dart';
import 'conversation_screen.dart';

/// The "Chat" tab: every user, tap one to start (or reopen) a 1:1 chat, or
/// toggle selection mode (the group-add icon) to pick several for a group —
/// same list either way, per how this was asked for.
class ContactsScreen extends StatelessWidget {
  final int currentUserId;
  const ContactsScreen({super.key, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ContactsViewModel(context.read<ApiClient>(), currentUserId),
      child: const _ContactsView(),
    );
  }
}

class _ContactsView extends StatelessWidget {
  const _ContactsView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ContactsViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: Text(vm.selectionMode ? 'New group · ${vm.selectedUserIds.length} selected' : 'Chat'),
        leading: vm.selectionMode
            ? IconButton(icon: const Icon(Icons.close), onPressed: vm.toggleSelectionMode)
            : null,
        actions: vm.selectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.check),
                  tooltip: 'Create group',
                  // Disabled (via null onPressed) rather than hidden below 2
                  // picks — same reasoning as the compose dialog's disabled
                  // Post button: a visible-but-inert control tells you the
                  // action exists and what's missing, instead of the control
                  // itself vanishing and re-appearing as you tap.
                  onPressed: vm.selectedUserIds.length >= 2 ? () => _showCreateGroupDialog(context, vm) : null,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.group_add_outlined),
                  tooltip: 'New group',
                  onPressed: vm.toggleSelectionMode,
                ),
                IconButton(icon: const Icon(Icons.refresh), onPressed: vm.load),
              ],
      ),
      body: Builder(
        builder: (context) {
          if (vm.isLoading && vm.contacts.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (vm.error != null) {
            return Center(child: Text(vm.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)));
          }
          if (vm.contacts.isEmpty) {
            return const Center(child: Text('No other users yet.'));
          }
          return ListView.separated(
            itemCount: vm.contacts.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _ContactRow(vm.contacts[index]),
          );
        },
      ),
    );
  }

  void _showCreateGroupDialog(BuildContext context, ContactsViewModel vm) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Name this group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Group name (optional)', border: OutlineInputBorder()),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Members: ${vm.selectedUsers.map((u) => '@${u.username}').join(', ')}',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final conversation = await vm.createGroup(controller.text);
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
              // Replace this picker with the conversation, not push on top of
              // it — a single "back" from the new group then lands directly
              // on the conversations list, not back through an empty picker.
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => ConversationScreen(
                    conversationId: conversation.id,
                    title: conversation.name ?? 'Group chat',
                  ),
                ),
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final User user;
  const _ContactRow(this.user);

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ContactsViewModel>();
    final selected = vm.selectedUserIds.contains(user.id);

    return ListTile(
      leading: vm.selectionMode
          ? Checkbox(value: selected, onChanged: (_) => vm.toggleSelected(user.id))
          : CircleAvatar(child: Text(user.username.isNotEmpty ? user.username[0].toUpperCase() : '?')),
      title: Text('@${user.username}'),
      subtitle: user.isCelebrity ? const Text('Celebrity') : null,
      trailing: !vm.selectionMode && user.isCelebrity ? const Icon(Icons.verified, size: 18) : null,
      onTap: vm.selectionMode
          ? () => vm.toggleSelected(user.id)
          : () async {
              final conversationId = await vm.openDirectConversation(user);
              if (!context.mounted) return;
              // Same replace-not-push reasoning as the group-creation flow.
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => ConversationScreen(
                    conversationId: conversationId,
                    title: '@${user.username}',
                  ),
                ),
              );
            },
    );
  }
}
