import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../profile/profile_screen.dart';
import '../profile/user_avatar.dart';
import '../session/current_user_provider.dart';
import 'communities_providers.dart';
import 'community.dart';

/// A community's members, join requests or bans. Moderators act on people
/// from here: approve or decline, remove or ban; the owner also appoints
/// moderators.
class CommunityMembersScreen extends ConsumerWidget {
  const CommunityMembersScreen({super.key, required this.community, required this.status});

  final Community community;
  final MembershipStatus status;

  static Future<void> open(BuildContext context, Community community, MembershipStatus status) =>
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CommunityMembersScreen(community: community, status: status)),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (communityId: community.id, status: status);
    final members = ref.watch(communityMembersProvider(key));
    // The latest version (your role may have changed since this opened).
    final c = ref.watch(communityProvider(community.id)).value ?? community;
    final me = ref.watch(currentUserProvider).value?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(switch (status) {
          MembershipStatus.active => 'Members',
          MembershipStatus.pending => 'Join requests',
          MembershipStatus.banned => 'Banned',
        }),
      ),
      body: switch (members) {
        AsyncData(:final value) when value.items.isEmpty => Center(
            child: Text(switch (status) {
              MembershipStatus.active => 'No members yet.',
              MembershipStatus.pending => 'No one is waiting to join.',
              MembershipStatus.banned => 'No one is banned.',
            }),
          ),
        AsyncData(:final value) => ListView(
            children: [
              for (final m in value.items) _MemberRow(community: c, member: m, isMe: m.user.id == me, listKey: key),
              if (value.hasMore)
                Center(
                  child: TextButton(
                    onPressed: () => ref.read(communityMembersProvider(key).notifier).loadMore(),
                    child: const Text('Load more'),
                  ),
                ),
            ],
          ),
        AsyncError() => Center(
            child: TextButton(
              onPressed: () => ref.invalidate(communityMembersProvider(key)),
              child: const Text('Couldn\'t load. Try again'),
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

enum _Action { approve, decline, makeModerator, makeMember, remove, ban, unban }

class _MemberRow extends ConsumerWidget {
  const _MemberRow({required this.community, required this.member, required this.isMe, required this.listKey});

  final Community community;
  final CommunityMember member;
  final bool isMe;
  final ({int communityId, MembershipStatus status}) listKey;

  /// What you may do to this person here (the server checks again).
  List<_Action> _actions() {
    if (isMe || !community.canModerate || member.role == CommunityRole.owner) return const [];
    final owner = community.isOwner;
    return switch (member.status) {
      MembershipStatus.pending => const [_Action.approve, _Action.decline, _Action.ban],
      MembershipStatus.banned => const [_Action.unban],
      MembershipStatus.active => [
          if (owner && member.role == CommunityRole.member) _Action.makeModerator,
          if (owner && member.role == CommunityRole.moderator) _Action.makeMember,
          // Only the owner can remove a moderator.
          if (owner || member.role == CommunityRole.member) ...[_Action.remove, _Action.ban],
        ],
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = _actions();
    final user = member.user;
    final role = switch (member.role) {
      CommunityRole.owner => 'Owner',
      CommunityRole.moderator => 'Moderator',
      CommunityRole.member => null,
    };
    return ListTile(
      leading: UserAvatar.of(user),
      title: Text(user.shownName),
      subtitle: Text([if (user.displayName != null) '@${user.username}', ?role].join(' · ')),
      onTap: () => ProfileScreen.open(context, user.id),
      trailing: actions.isEmpty
          ? null
          : PopupMenuButton<_Action>(
              onSelected: (action) => _perform(context, ref, action),
              itemBuilder: (_) => [
                for (final a in actions)
                  PopupMenuItem(
                    value: a,
                    child: Text(switch (a) {
                      _Action.approve => 'Approve',
                      _Action.decline => 'Decline',
                      _Action.makeModerator => 'Make moderator',
                      _Action.makeMember => 'Remove as moderator',
                      _Action.remove => 'Remove from community',
                      _Action.ban => 'Ban',
                      _Action.unban => 'Lift ban',
                    }),
                  ),
              ],
            ),
    );
  }

  Future<void> _perform(BuildContext context, WidgetRef ref, _Action action) async {
    final notifier = ref.read(communityMembersProvider(listKey).notifier);
    final id = member.user.id;
    if (action == _Action.ban) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text('Ban ${member.user.shownName}?'),
          content: const Text('They\'ll be removed and can\'t join again unless the ban is lifted.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('Ban')),
          ],
        ),
      );
      if (sure != true) return;
    }
    try {
      await switch (action) {
        _Action.approve => notifier.approve(id),
        _Action.decline || _Action.remove || _Action.unban => notifier.remove(id),
        _Action.ban => notifier.remove(id, ban: true),
        _Action.makeModerator => notifier.setRole(id, CommunityRole.moderator),
        _Action.makeMember => notifier.setRole(id, CommunityRole.member),
      };
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That didn\'t work. Try again.')));
      }
    }
  }
}
