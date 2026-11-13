import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/api_service.dart';
import '../profile/user_avatar.dart';
import 'communities_api.dart';
import 'communities_providers.dart';
import 'community.dart';
import 'community_screen.dart';

/// "Join with an invite": paste a link (or just its code), see which
/// community it's for, then join, straight in, even a private one.
Future<void> showJoinWithInvite(BuildContext context) =>
    showDialog(context: context, builder: (_) => const _JoinWithInviteDialog());

class _JoinWithInviteDialog extends ConsumerStatefulWidget {
  const _JoinWithInviteDialog();

  @override
  ConsumerState<_JoinWithInviteDialog> createState() => _JoinWithInviteDialogState();
}

class _JoinWithInviteDialogState extends ConsumerState<_JoinWithInviteDialog> {
  final _link = TextEditingController();
  InvitePreview? _preview;
  String? _code;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _look() async {
    final code = CommunityInvite.codeFrom(_link.text);
    if (code == null) return setState(() => _error = 'That doesn\'t look like an invite link.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await ref.read(communitiesApiProvider).previewInvite(code);
      if (mounted) {
        setState(() {
          _preview = preview;
          _code = code;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.statusCode == 404 ? 'This invite link doesn\'t exist.' : 'Couldn\'t check it.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t check it. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      final community = await ref.read(communitiesApiProvider).acceptInvite(_code!);
      ref.invalidate(joinedCommunitiesProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      await CommunityScreen.open(context, community.id);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = switch (e.statusCode) {
              403 => 'You can\'t join this community.',
              410 => 'This invite no longer works.',
              _ => 'Couldn\'t join. Try again.',
            });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final community = preview?.community;
    return AlertDialog(
      title: const Text('Join with an invite'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (community == null)
            TextField(
              key: const Key('invite-link'),
              controller: _link,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Invite link or code', border: OutlineInputBorder()),
              onSubmitted: (_) => _look(),
            )
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: UserAvatar(name: community.name, photo: community.photo),
              title: Text(community.name),
              subtitle: Text(
                preview!.works
                    ? '${community.isPrivate ? 'Private' : 'Public'} · ${community.memberCount} members'
                    : preview.reason ?? 'This invite no longer works.',
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        if (community == null)
          FilledButton(onPressed: _busy ? null : _look, child: const Text('Next'))
        else if (community.isMember)
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              CommunityScreen.open(context, community.id);
            },
            child: const Text('You\'re in · Open'),
          )
        else if (preview!.works)
          FilledButton(onPressed: _busy ? null : _join, child: Text('Join ${community.name}')),
      ],
    );
  }
}
