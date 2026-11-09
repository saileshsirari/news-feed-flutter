import 'package:flutter/material.dart';

import '../models/models.dart';
import 'emoji_picking.dart';
import 'reactions.dart';

/// Long-pressing a message: the quick reactions (your current one
/// highlighted; picking it again removes it), ➕ for any emoji, and for
/// your own messages, Message info.
Future<void> showMessageActions(
  BuildContext context, {
  required ChatMessage message,
  required int currentUserId,
  required void Function(String emoji) onReact,
  VoidCallback? onInfo,
}) {
  String? mine;
  for (final r in message.reactions) {
    if (r.userIds.contains(currentUserId)) mine = r.emoji;
  }
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              key: const Key('quick-reactions'),
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final emoji in quickReactions)
                  _ReactionChoice(
                    emoji: emoji,
                    selected: emoji == mine,
                    onTap: () {
                      Navigator.of(sheet).pop();
                      onReact(emoji);
                    },
                  ),
                IconButton(
                  tooltip: 'More emojis',
                  icon: const Icon(Icons.add_reaction_outlined),
                  onPressed: () async {
                    Navigator.of(sheet).pop();
                    final emoji = await pickEmoji(context);
                    if (emoji != null) onReact(emoji);
                  },
                ),
              ],
            ),
          ),
          if (onInfo != null)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Message info'),
              onTap: () {
                Navigator.of(sheet).pop();
                onInfo();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _ReactionChoice extends StatelessWidget {
  const _ReactionChoice({required this.emoji, required this.selected, required this.onTap});

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: selected
              ? BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, shape: BoxShape.circle)
              : null,
          child: Text(emoji, style: const TextStyle(fontSize: 28)),
        ),
      );
}

/// The reactions under a message: "❤️ 2  😂 1", yours highlighted. Tapping
/// shows who reacted, and lets you take yours back.
class ReactionChips extends StatelessWidget {
  const ReactionChips({
    super.key,
    required this.message,
    required this.currentUserId,
    required this.usernames,
    required this.onRemoveMine,
  });

  final ChatMessage message;
  final int currentUserId;
  final Map<int, String> usernames;
  final VoidCallback onRemoveMine;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 4,
      children: [
        for (final r in message.reactions)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showWho(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: r.userIds.contains(currentUserId) ? colors.primaryContainer : colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Text(r.userIds.length > 1 ? '${r.emoji} ${r.userIds.length}' : r.emoji),
            ),
          ),
      ],
    );
  }

  void _showWho(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final r in message.reactions)
                for (final id in r.userIds)
                  ListTile(
                    leading: Text(r.emoji, style: const TextStyle(fontSize: 24)),
                    title: Text(id == currentUserId ? 'You' : '@${usernames[id] ?? 'user $id'}'),
                    subtitle: id == currentUserId ? const Text('Tap to remove') : null,
                    onTap: id == currentUserId
                        ? () {
                            Navigator.of(sheet).pop();
                            onRemoveMine();
                          }
                        : null,
                  ),
            ],
          ),
        ),
      );
}
