import 'package:flutter/material.dart';
import 'package:shared_media/shared_media.dart';

import '../models/models.dart';
import '../profile/profile_screen.dart';
import '../profile/user_avatar.dart';
import 'comments_sheet.dart';

/// One post: who wrote it (tap for their profile), what they wrote, its
/// photos and videos, and ♡ like / 💬 comments. Shown in the feed and on
/// profiles; each passes how liking and comment counts update its own list.
class PostCard extends StatelessWidget {
  const PostCard(this.post, {super.key, required this.onLike, required this.onCommentCount, this.linkToAuthor = true});

  final Post post;
  final VoidCallback onLike;
  final ValueChanged<int> onCommentCount;

  /// False on the author's own profile (it's already open).
  final bool linkToAuthor;

  @override
  Widget build(BuildContext context) {
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          linkToAuthor
              ? InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => ProfileScreen.open(context, post.authorId),
                  child: author,
                )
              : author,
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
