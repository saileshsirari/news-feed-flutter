import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/service_providers.dart';
import 'communities_api.dart';
import 'community.dart';

/// A community's invite links, for its moderators: make one (for a day, a
/// week or for good; for one person, ten, or anyone), copy it to share,
/// or turn it off. Whoever opens one joins straight away, private or not.
class CommunityInvitesScreen extends ConsumerStatefulWidget {
  const CommunityInvitesScreen({super.key, required this.community});

  final Community community;

  static Future<void> open(BuildContext context, Community community) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => CommunityInvitesScreen(community: community)));

  @override
  ConsumerState<CommunityInvitesScreen> createState() => _CommunityInvitesScreenState();
}

class _CommunityInvitesScreenState extends ConsumerState<CommunityInvitesScreen> {
  late Future<List<CommunityInvite>> _invites = _load();

  CommunitiesApi get _api => ref.read(communitiesApiProvider);

  Future<List<CommunityInvite>> _load() => ref.read(communitiesApiProvider).invites(widget.community.id);

  void _reload() => setState(() => _invites = _load());

  String _link(CommunityInvite invite) => invite.link(ref.read(appConfigProvider).apiBaseUrl);

  Future<void> _copy(CommunityInvite invite) async {
    await Clipboard.setData(ClipboardData(text: 'Join ${widget.community.name}: ${_link(invite)}'));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite link copied')));
  }

  Future<void> _create() async {
    final choice = await showModalBottomSheet<({int? hours, int? uses})>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _NewInviteSheet(),
    );
    if (choice == null) return;
    try {
      final invite = await _api.createInvite(widget.community.id, expiresInHours: choice.hours, maxUses: choice.uses);
      _reload();
      await _copy(invite);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t make a link. Try again.')));
      }
    }
  }

  Future<void> _revoke(CommunityInvite invite) async {
    try {
      await _api.revokeInvite(widget.community.id, invite.code);
      _reload();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t turn it off.')));
    }
  }

  static String _describe(CommunityInvite invite) {
    final uses = invite.maxUses == null ? '${invite.uses} used' : '${invite.uses} of ${invite.maxUses} used';
    final expiresAt = invite.expiresAt;
    if (expiresAt == null) return '$uses · never expires';
    final left = DateTime.fromMillisecondsSinceEpoch(expiresAt).difference(DateTime.now());
    final when = left.inHours >= 48 ? '${left.inDays} days' : left.inHours >= 1 ? '${left.inHours} hours' : 'under an hour';
    return '$uses · expires in $when';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invite links')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_link),
        label: const Text('New link'),
      ),
      body: FutureBuilder(
        future: _invites,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: TextButton(onPressed: _reload, child: const Text('Couldn\'t load. Try again')));
          }
          final invites = snapshot.data;
          if (invites == null) return const Center(child: CircularProgressIndicator());
          if (invites.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No invite links yet. Anyone with a link joins straight away, even if the community is private.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              for (final invite in invites)
                ListTile(
                  leading: const Icon(Icons.link),
                  title: Text(_link(invite), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_describe(invite)),
                  onTap: () => _copy(invite),
                  trailing: IconButton(
                    icon: const Icon(Icons.link_off),
                    tooltip: 'Turn off this link',
                    onPressed: () => _revoke(invite),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// How long a new link works, and for how many people.
class _NewInviteSheet extends StatefulWidget {
  const _NewInviteSheet();

  @override
  State<_NewInviteSheet> createState() => _NewInviteSheetState();
}

class _NewInviteSheetState extends State<_NewInviteSheet> {
  int? _hours = 24 * 7;
  int? _uses;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Works for', style: textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<int?>(
              segments: const [
                ButtonSegment(value: 24, label: Text('1 day')),
                ButtonSegment(value: 24 * 7, label: Text('7 days')),
                ButtonSegment(value: null, label: Text('Always')),
              ],
              selected: {_hours},
              onSelectionChanged: (s) => setState(() => _hours = s.first),
            ),
            const SizedBox(height: 16),
            Text('Lets in', style: textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<int?>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1 person')),
                ButtonSegment(value: 10, label: Text('10 people')),
                ButtonSegment(value: null, label: Text('Anyone')),
              ],
              selected: {_uses},
              onSelectionChanged: (s) => setState(() => _uses = s.first),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop((hours: _hours, uses: _uses)),
                child: const Text('Make link and copy it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
