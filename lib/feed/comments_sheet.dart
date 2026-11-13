import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../session/current_user_provider.dart';
import 'comment_composer.dart';
import 'comment_row.dart';
import 'comments_notifier.dart';
import 'feed_notifier.dart';

/// A post's comments as threads: each comment, then its replies, indented,
/// three levels deep (deeper ones open with "Continue this thread"). Reply
/// to any comment; delete your own, or any on your own post. New comments
/// from others arrive live while it's open. [onCountChanged] keeps the
/// count under the post right (by default, in the feed).
Future<void> showComments(
  BuildContext context,
  Post post, {
  ValueChanged<int>? onCountChanged,
  PostComment? thread,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: CommentsSheet(post: post, onCountChanged: onCountChanged, thread: thread),
      ),
    );

/// Layout only: the logic is CommentsNotifier's, one comment is a
/// CommentRow, and the box at the bottom is a CommentComposer.
class CommentsSheet extends ConsumerWidget {
  const CommentsSheet({super.key, required this.post, this.onCountChanged, this.thread});
  final Post post;
  final ValueChanged<int>? onCountChanged;

  /// Set for "Continue this thread": just this comment and its replies.
  final PostComment? thread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = CommentsKey(post, thread);
    final vm = ref.watch(commentsProvider(key));
    final notifier = ref.read(commentsProvider(key).notifier);
    final me = ref.watch(currentUserProvider).value?.id;
    final textTheme = Theme.of(context).textTheme;

    // Keep the count under the post (in the feed, or a profile) in step.
    ref.listen(commentsProvider(key).select((s) => s.count), (_, count) {
      final onCountChanged = this.onCountChanged;
      if (onCountChanged != null) {
        onCountChanged(count);
      } else {
        ref.read(feedProvider.notifier).setCommentCount(post.id, count);
      }
    });

    final comments = vm.comments;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(thread == null ? 'Comments' : 'Thread', style: textTheme.titleMedium),
        ),
        if (vm.unseen > 0)
          TextButton.icon(
            onPressed: notifier.load,
            icon: const Icon(Icons.arrow_upward, size: 16),
            label: Text('${vm.unseen} new ${vm.unseen == 1 ? 'comment' : 'comments'}'),
          ),
        if (vm.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(vm.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Expanded(
          child: vm.isLoading && comments.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : comments.isEmpty
                  ? const Center(child: Text('No comments yet. Be the first.'))
                  : ListView.builder(
                      itemCount: comments.length + (vm.nextCursor != null ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == comments.length) {
                          return TextButton(
                            onPressed: vm.isLoading ? null : () => notifier.load(more: true),
                            child: const Text('Load more'),
                          );
                        }
                        final c = comments[i];
                        return CommentRow(
                          key: ValueKey(c.id),
                          comment: c,
                          indent: vm.indentOf(c),
                          canDelete: !c.deleted && (c.authorId == me || post.authorId == me || post.canModerate),
                          continues: vm.continuesElsewhere(c),
                          onReply: () => notifier.startReply(c),
                          onDelete: () => notifier.delete(c),
                          // Its own sheet, from this comment down.
                          onContinue: () => showComments(context, post, onCountChanged: onCountChanged, thread: c),
                        );
                      },
                    ),
        ),
        CommentComposer(
          replyTo: vm.replyTo,
          isSending: vm.isSending,
          isReply: thread != null,
          onSend: notifier.send,
          onCancelReply: notifier.cancelReply,
        ),
      ],
    );
  }
}
