import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/api_service.dart';
import '../profile/user_avatar.dart';
import 'communities_api.dart';
import 'communities_providers.dart';
import 'community.dart';
import 'community_invites_screen.dart';
import 'community_members_screen.dart';
import '../chat/conversation_screen.dart';
import 'edit_community_screen.dart';
import '../feed/compose_post_dialog.dart';
import '../feed/post_card.dart';

/// One community: who it's for, how many are in it, and your part in it
/// (join, requested, leave). The owner edits or deletes it; moderators see
/// join requests and invite links. Members post here and chat together.
class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key, required this.communityId});

  final int communityId;

  static Future<void> open(BuildContext context, int communityId) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommunityScreen(communityId: communityId)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final community = ref.watch(communityProvider(communityId));
    return Scaffold(
      appBar: AppBar(
        title: Text(community.value?.name ?? 'Community'),
        actions: [
          if (community.value case final c? when c.isOwner)
            PopupMenuButton<String>(
              onSelected: (action) => switch (action) {
                'edit' => EditCommunityScreen.edit(context, c),
                _ => _confirmDelete(context, ref, c),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'))),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete community')),
                ),
              ],
            ),
        ],
      ),
      body: switch (community) {
        AsyncData(:final value) => RefreshIndicator(
            onRefresh: () => ref.refresh(communityProvider(communityId).future),
            child: ListView(children: [_Header(value), _Sections(value), _Posts(value)]),
          ),
        AsyncError() => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Couldn\'t load this community. It may have been deleted.'),
                TextButton(onPressed: () => ref.invalidate(communityProvider(communityId)), child: const Text('Try again')),
              ],
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Community community) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Delete ${community.name}?'),
        content: const Text('It disappears for all its members. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    try {
      await ref.read(communitiesApiProvider).delete(community.id);
      ref.invalidate(joinedCommunitiesProvider);
      ref.invalidate(discoverCommunitiesProvider);
      if (context.mounted) Navigator.of(context).pop();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t delete it. Try again.')));
      }
    }
  }
}

class _Header extends ConsumerStatefulWidget {
  const _Header(this.community);
  final Community community;

  @override
  ConsumerState<_Header> createState() => _HeaderState();
}

class _HeaderState extends ConsumerState<_Header> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String failed) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) {
        final message = e.statusCode == 403 ? 'You can\'t join this community.' : failed;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.community;
    final notifier = ref.read(communityProvider(c.id).notifier);
    final textTheme = Theme.of(context).textTheme;

    final Widget action = switch (c.myStatus) {
      _ when c.isOwner => const SizedBox.shrink(),
      MembershipStatus.active => OutlinedButton.icon(
          onPressed: _busy ? null : () => _run(notifier.leave, 'Couldn\'t leave. Try again.'),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Joined · Leave'),
        ),
      MembershipStatus.pending => OutlinedButton(
          onPressed: _busy ? null : () => _run(notifier.leave, 'Couldn\'t cancel. Try again.'),
          child: const Text('Requested · Cancel'),
        ),
      MembershipStatus.banned => const Text('You can\'t join this community.'),
      null => FilledButton(
          onPressed: _busy ? null : () => _run(notifier.join, 'Couldn\'t join. Try again.'),
          child: Text(c.isPrivate ? 'Ask to join' : 'Join'),
        ),
    };

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(name: c.name, photo: c.photo, radius: 36),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(c.isPrivate ? Icons.lock_outline : Icons.public, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '${c.isPrivate ? 'Private' : 'Public'} · ${c.memberCount} '
                          '${c.memberCount == 1 ? 'member' : 'members'}',
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (c.description != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(c.description!)),
          const SizedBox(height: 12),
          if (c.isOwner) Text('You own this community.', style: textTheme.bodySmall) else action,
        ],
      ),
    );
  }
}

/// Members (and, for moderators, join requests and bans).
class _Sections extends ConsumerWidget {
  const _Sections(this.community);
  final Community community;

  /// Opens (and the first time, makes) the community's group chat.
  Future<void> _openChat(BuildContext context, WidgetRef ref) async {
    try {
      final conversationId = await ref.read(communitiesApiProvider).chat(community.id);
      if (!context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ConversationScreen(conversationId: conversationId, title: community.name),
      ));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t open the chat. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = community;
    final canSeeMembers = !c.isPrivate || c.isMember;
    return Column(
      children: [
        const Divider(),
        if (c.isMember)
          ListTile(
            leading: const Icon(Icons.forum_outlined),
            title: const Text('Chat'),
            subtitle: const Text('Everyone in the community'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openChat(context, ref),
          ),
        ListTile(
          leading: const Icon(Icons.group_outlined),
          title: const Text('Members'),
          subtitle: canSeeMembers ? null : const Text('Only members can see who\'s in it'),
          trailing: canSeeMembers ? const Icon(Icons.chevron_right) : null,
          enabled: canSeeMembers,
          onTap: () => CommunityMembersScreen.open(context, c, MembershipStatus.active),
        ),
        if (c.canModerate && c.isPrivate)
          ListTile(
            leading: const Icon(Icons.how_to_reg_outlined),
            title: const Text('Join requests'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => CommunityMembersScreen.open(context, c, MembershipStatus.pending),
          ),
        if (c.canModerate)
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Invite links'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => CommunityInvitesScreen.open(context, c),
          ),
        if (c.canModerate)
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('Banned'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => CommunityMembersScreen.open(context, c, MembershipStatus.banned),
          ),
      ],
    );
  }
}

/// The community's posts: members write them; anyone who can see the
/// community reads them; its moderators can remove any.
class _Posts extends ConsumerWidget {
  const _Posts(this.community);
  final Community community;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = community;
    final textTheme = Theme.of(context).textTheme;
    if (c.isPrivate && !c.isMember) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Posts in a private community are for its members.')),
      );
    }
    final posts = ref.watch(communityPostsProvider(c.id));
    final notifier = ref.read(communityPostsProvider(c.id).notifier);

    Future<void> act(Future<void> Function() action, String failed) async {
      try {
        await action();
      } catch (_) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failed)));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              Expanded(child: Text('Posts', style: textTheme.titleMedium)),
              if (c.isMember)
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Write a post'),
                  onPressed: () => showComposePostDialog(
                    context,
                    // Its own draft, so files picked for the feed don't show up here.
                    draftKey: (id: 'community:${c.id}', maxItems: 10, sealed: false),
                    title: 'Post in ${c.name}',
                    onPost: (body, mediaIds) => act(() => notifier.publish(body, mediaIds), 'Couldn\'t post. Try again.'),
                  ),
                ),
            ],
          ),
        ),
        ...switch (posts) {
          AsyncData(:final value) when value.items.isEmpty => [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(c.isMember ? 'No posts yet. Write the first one!' : 'No posts yet.')),
              ),
            ],
          AsyncData(:final value) => [
              for (final post in value.items) ...[
                PostCard(
                  post,
                  showCommunity: false,
                  onLike: () => c.isMember
                      ? notifier.toggleLike(post.id)
                      : ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Join the community to like and comment.')),
                        ),
                  onCommentCount: (count) => notifier.setCommentCount(post.id, count),
                  onDelete: () => act(() => notifier.delete(post.id), 'Couldn\'t delete it. Try again.'),
                ),
                const Divider(height: 1),
              ],
              if (value.hasMore)
                Center(
                  child: TextButton(onPressed: notifier.loadMore, child: const Text('Load more')),
                ),
            ],
          AsyncError() => [
              Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(communityPostsProvider(c.id)),
                  child: const Text('Couldn\'t load posts. Try again'),
                ),
              ),
            ],
          _ => [const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))],
        },
      ],
    );
  }
}
