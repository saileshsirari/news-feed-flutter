import 'package:flutter/material.dart';

import '../models/models.dart';

/// One comment in a thread: indented under its parent, with Reply, Delete
/// (if you may) and "Continue this thread" (if its replies are too deep to
/// show here). A deleted one with replies shows as [deleted].
class CommentRow extends StatelessWidget {
  const CommentRow({
    super.key,
    required this.comment,
    required this.indent,
    required this.canDelete,
    required this.continues,
    required this.onReply,
    required this.onDelete,
    required this.onContinue,
  });

  final PostComment comment;

  /// Levels below the sheet's top level.
  final int indent;
  final bool canDelete;
  final bool continues;
  final VoidCallback onReply;
  final VoidCallback onDelete;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final c = comment;
    final compact = TextButton.styleFrom(visualDensity: VisualDensity.compact);

    return Padding(
      padding: EdgeInsets.only(left: 16.0 + 20.0 * indent, right: 8, top: 6),
      child: DecoratedBox(
        // A line down the left of replies, like most threaded apps.
        decoration: BoxDecoration(
          border: indent > 0 ? Border(left: BorderSide(color: colors.outlineVariant, width: 2)) : const Border(),
        ),
        child: Padding(
          padding: EdgeInsets.only(left: indent > 0 ? 10 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (c.deleted)
                Text('[deleted]', style: textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: colors.outline))
              else ...[
                Text('@${c.authorUsername}', style: textTheme.labelLarge),
                Text(c.body),
              ],
              Wrap(
                children: [
                  if (!c.deleted)
                    TextButton(key: Key('reply-${c.id}'), onPressed: onReply, style: compact, child: const Text('Reply')),
                  if (canDelete) TextButton(onPressed: onDelete, style: compact, child: const Text('Delete')),
                  if (continues)
                    TextButton(
                      key: Key('continue-${c.id}'),
                      onPressed: onContinue,
                      style: compact,
                      child: Text('Continue this thread (${c.replyCount}) →'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
