import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_media/shared_media.dart';

import '../communities/community_screen.dart';
import '../models/models.dart';
import '../session/current_user_provider.dart';
import '../profile/profile_screen.dart';
import '../profile/user_avatar.dart';
import 'comments_sheet.dart';

/// One post: who wrote it (tap for their profile), where (a community, tap
/// to open it), what they wrote, its photos and videos, and ♡ like /
/// 💬 comments. Its author, or a moderator of its community, gets ⋮ Delete.
/// Shown in the feed, on profiles and in communities; each passes how
/// liking, comment counts and deleting update its own list.
class PostCard extends ConsumerWidget {
  const PostCard(
    this.post, {
    super.key,
    required this.onLike,
    required this.onCommentCount,
    this.onDelete,
    this.linkToAuthor = true,
    this.showCommunity = true,
  });

  final Post post;
  final VoidCallback onLike;
  final ValueChanged<int> onCommentCount;

  /// Null where deleting isn't offered.
  final VoidCallback? onDelete;

  /// False on the author's own profile (it's already open).
  final bool linkToAuthor;

  /// False inside its own community (you're already there).
  final bool showCommunity;

  Future<void> _confirmDelete(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete this post?'),
        content: const Text('It disappears for everyone, with its comments. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (sure == true) onDelete?.call();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider).value?.id;
    final community = post.community;
    final textTheme = Theme.of(context).textTheme;
    final time = DateTime.fromMillisecondsSinceEpoch(post.createdAt);
    final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final author = Row(
      children: [
        UserAvatar(name: post.authorDisplayName ?? post.authorUsername, photo: post.authorPhoto, radius: 18),
        const SizedBox(width: 10),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                if (post.authorDisplayName != null)
                  TextSpan(text: '${post.authorDisplayName}  ', style: textTheme.titleSmall),
                TextSpan(
                  text: '@${post.authorUsername}',
                  style: post.authorDisplayName == null ? textTheme.titleSmall : textTheme.bodySmall,
                ),
              ],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(timeStr, style: textTheme.bodySmall),
      ],
    );
    final canDelete = onDelete != null && post.canBeDeletedBy(me);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: linkToAuthor
                    ? InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => ProfileScreen.open(context, post.authorId),
                        child: author,
                      )
                    : author,
              ),
              if (canDelete)
                PopupMenuButton<String>(
                  tooltip: 'Post options',
                  onSelected: (_) => _confirmDelete(context),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'delete',
                      // A moderator removing someone else's post says so.
                      child: Text(post.authorId == me ? 'Delete post' : 'Remove post (moderator)'),
                    ),
                  ],
                ),
            ],
          ),
          if (showCommunity && community != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InkWell(
                onTap: () => CommunityScreen.open(context, community.id),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.groups_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 4),
                    Text('in ${community.name}', style: textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
                  ],
                ),
              ),
            ),
          if (post.body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(post.body)),
          if (post.media.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: MediaGrid(media: post.media),
            ),
          _PostActions(post, onLike: onLike, onCommentCount: onCommentCount),
        ],
      ),
    );
  }
}

/// ♡ like and 💬 comments, with their counts.
class _PostActions extends StatelessWidget {
  const _PostActions(this.post, {required this.onLike, required this.onCommentCount});
  final Post post;
  final VoidCallback onLike;
  final ValueChanged<int> onCommentCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          TextButton.icon(
            key: Key('like-${post.id}'),
            onPressed: onLike,
            icon: Icon(
              post.likedByMe ? Icons.favorite : Icons.favorite_border,
              color: post.likedByMe ? Colors.red : colors.onSurfaceVariant,
            ),
            label: Text(post.likeCount > 0 ? '${post.likeCount}' : 'Like'),
          ),
          TextButton.icon(
            key: Key('comments-${post.id}'),
            onPressed: () => showComments(context, post, onCountChanged: onCommentCount),
            icon: Icon(Icons.chat_bubble_outline, color: colors.onSurfaceVariant),
            label: Text(post.commentCount > 0 ? '${post.commentCount}' : 'Comment'),
          ),
        ],
      ),
    );
  }
}
