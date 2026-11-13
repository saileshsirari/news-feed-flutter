import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/api_service.dart';
import '../profile/user_avatar.dart';
import 'communities_api.dart';
import 'communities_providers.dart';
import 'community.dart';
import 'community_members_screen.dart';
import 'edit_community_screen.dart';

/// One community: who it's for, how many are in it, and your part in it
/// (join, requested, leave). The owner edits or deletes it; moderators see
/// join requests. Its posts and chat come in the next phases.
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
            child: ListView(children: [_Header(value), _Sections(value)]),
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
class _Sections extends StatelessWidget {
  const _Sections(this.community);
  final Community community;

  @override
  Widget build(BuildContext context) {
    final c = community;
    final canSeeMembers = !c.isPrivate || c.isMember;
    return Column(
      children: [
        const Divider(),
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
            leading: const Icon(Icons.block),
            title: const Text('Banned'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => CommunityMembersScreen.open(context, c, MembershipStatus.banned),
          ),
      ],
    );
  }
}
