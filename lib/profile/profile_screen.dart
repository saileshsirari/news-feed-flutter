import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/conversation_screen.dart';
import '../data/services/service_providers.dart';
import '../feed/post_card.dart';
import '../follow/follow_button.dart';
import '../models/models.dart';
import '../session/current_user_provider.dart';
import 'edit_profile_screen.dart';
import 'profile_notifier.dart';
import 'user_avatar.dart';

/// Someone's profile: photo, name, @handle, bio, counts, and their posts.
/// Yours has "Edit profile"; anyone else's has Follow and Message.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, required this.userId});

  final int userId;

  static Future<void> open(BuildContext context, int userId) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider(userId));
    final notifier = ref.read(profileProvider(userId).notifier);
    ref.listen(profileProvider(userId).select((p) => p.value?.error), (_, error) {
      if (error == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      notifier.dismissError();
    });

    return Scaffold(
      appBar: AppBar(title: Text(profile.value?.user.shownName ?? 'Profile')),
      body: switch (profile) {
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: () => ref.refresh(profileProvider(userId).future),
          child: ListView.separated(
            itemCount: value.posts.length + 2,
            separatorBuilder: (_, index) => index == 0 ? const SizedBox.shrink() : const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) return _Header(value.user);
              if (index <= value.posts.length) {
                final post = value.posts[index - 1];
                return PostCard(
                  post,
                  linkToAuthor: false,
                  onLike: () => notifier.toggleLike(post.id),
                  onCommentCount: (count) => notifier.setCommentCount(post.id, count),
                  onDelete: () => notifier.deletePost(post.id),
                );
              }
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: value.isLoadingMore
                      ? const CircularProgressIndicator()
                      : value.nextCursor != null
                      ? TextButton(onPressed: notifier.loadMore, child: const Text('Load more'))
                      : value.posts.isEmpty
                      ? const Text('No posts yet.')
                      : const SizedBox.shrink(),
                ),
              );
            },
          ),
        ),
        AsyncError() => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Couldn\'t load this profile.'),
              TextButton(onPressed: () => ref.invalidate(profileProvider(userId)), child: const Text('Try again')),
            ],
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header(this.user);

  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final isMe = ref.watch(currentUserProvider).value?.id == user.id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar.of(user, radius: 40),
              const SizedBox(width: 20),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Count(user.postCount, 'Posts'),
                    _Count(user.followerCount, 'Followers'),
                    _Count(user.followingCount, 'Following'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(child: Text(user.displayName ?? user.username, style: textTheme.titleMedium)),
              if (user.isCelebrity)
                const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified, size: 18)),
            ],
          ),
          Text('@${user.username}', style: textTheme.bodySmall),
          if (user.bio != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(user.bio!)),
          const SizedBox(height: 12),
          if (isMe)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => EditProfileScreen.open(context, user),
                child: const Text('Edit profile'),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: FollowButton(userId: user.id, username: user.username),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Message'),
                    onPressed: () => _message(context, ref),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Opens (or starts) your 1:1 chat with them.
  Future<void> _message(BuildContext context, WidgetRef ref) async {
    final me = ref.read(currentUserProvider).requireValue!.id;
    try {
      final conversation = await ref
          .read(apiServiceProvider)
          .createConversation(participantIds: [me, user.id], isGroup: false);
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ConversationScreen(conversationId: conversation.id, title: user.shownName, otherUserId: user.id),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Couldn\'t open the chat. Try again.')));
      }
    }
  }
}

class _Count extends StatelessWidget {
  const _Count(this.value, this.label);

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('$value', style: Theme.of(context).textTheme.titleMedium),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
