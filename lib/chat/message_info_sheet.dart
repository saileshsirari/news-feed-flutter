import 'package:flutter/material.dart';

import '../models/models.dart';
import 'conversation_notifier.dart';

/// WhatsApp's "Message info" for one of your messages: who has read it,
/// who has it on their device but hasn't read it, and who doesn't have it
/// yet. From the read and delivered pointers the chat already keeps.
Future<void> showMessageInfo(BuildContext context, ChatMessage message, ConversationState state, int currentUserId) {
  final others = state.usernameByUserId.keys.where((id) => id != currentUserId).toList();
  String name(int id) => '@${state.usernameByUserId[id] ?? 'user $id'}';
  final read = [
    for (final id in others)
      if ((state.readStateByUserId[id] ?? 0) >= message.id) id,
  ];
  final delivered = [
    for (final id in others)
      if (!read.contains(id) && (state.deliveredByUserId[id] ?? 0) >= message.id) id,
  ];
  final waiting = [
    for (final id in others)
      if (!read.contains(id) && !delivered.contains(id)) id,
  ];

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      Widget section(String title, Widget icon, List<int> ids) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            dense: true,
            leading: icon,
            title: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          for (final id in ids)
            ListTile(dense: true, contentPadding: const EdgeInsets.only(left: 72), title: Text(name(id))),
        ],
      );
      return SafeArea(
        child: ListView(
          key: const Key('message-info'),
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Message info', style: Theme.of(context).textTheme.titleMedium),
            ),
            if (others.isEmpty) const ListTile(title: Text('Loading who\'s in this chat…')),
            if (read.isNotEmpty) section('Read by', const TickIcon(MessageTick.read), read),
            if (delivered.isNotEmpty) section('Delivered to', const TickIcon(MessageTick.delivered), delivered),
            if (waiting.isNotEmpty) section('Not delivered yet', const TickIcon(MessageTick.sent), waiting),
          ],
        ),
      );
    },
  );
}

/// ✓ / ✓✓ / blue ✓✓, as in WhatsApp.
class TickIcon extends StatelessWidget {
  const TickIcon(this.tick, {super.key, this.size = 16});

  final MessageTick tick;
  final double size;

  @override
  Widget build(BuildContext context) {
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    return switch (tick) {
      MessageTick.sent => Icon(Icons.done, size: size, color: grey, semanticLabel: 'Sent'),
      MessageTick.delivered => Icon(Icons.done_all, size: size, color: grey, semanticLabel: 'Delivered'),
      MessageTick.read => Icon(Icons.done_all, size: size, color: Colors.lightBlue, semanticLabel: 'Read'),
    };
  }
}
