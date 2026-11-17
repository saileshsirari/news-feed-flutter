import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/service_providers.dart';
import 'org.dart';
import 'orgs_api.dart';
import 'orgs_controller.dart';

/// An organisation's invite links, for its owners and admins: make one
/// (for a day, a week or for good; for one person, ten, or anyone; or for
/// one email address), copy it to share, or turn it off. Whoever opens one
/// joins the organisation.
class OrgInvitesScreen extends ConsumerStatefulWidget {
  const OrgInvitesScreen({super.key, required this.org});

  final Org org;

  static Future<void> open(BuildContext context, Org org) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OrgInvitesScreen(org: org)));

  @override
  ConsumerState<OrgInvitesScreen> createState() => _OrgInvitesScreenState();
}

class _OrgInvitesScreenState extends ConsumerState<OrgInvitesScreen> {
  late final OrgsApi _api = ref.read(orgsProvider.notifier).api;
  late Future<List<OrgInvite>> _invites = _api.invites(widget.org.id);

  void _reload() => setState(() => _invites = _api.invites(widget.org.id));

  String _link(OrgInvite invite) => invite.link(ref.read(appConfigProvider).apiBaseUrl);

  Future<void> _copy(OrgInvite invite) async {
    await Clipboard.setData(ClipboardData(text: 'Join ${widget.org.name}: ${_link(invite)}'));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite link copied')));
  }

  Future<void> _create() async {
    final choice = await showModalBottomSheet<_NewInvite>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _NewInviteSheet(),
    );
    if (choice == null) return;
    try {
      final invite = await _api.createInvite(
        widget.org.id,
        expiresInHours: choice.hours,
        maxUses: choice.uses,
        email: choice.email,
      );
      _reload();
      await _copy(invite);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t make a link. Try again.')));
      }
    }
  }

  Future<void> _revoke(OrgInvite invite) async {
    try {
      await _api.revokeInvite(widget.org.id, invite.code);
      _reload();
    } on Object {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t turn it off.')));
    }
  }

  static String describe(OrgInvite invite, {DateTime? now}) {
    final uses = invite.maxUses == null ? '${invite.uses} used' : '${invite.uses} of ${invite.maxUses} used';
    final who = invite.email == null ? '' : 'for ${invite.email} · ';
    final expiresAt = invite.expiresAt;
    if (expiresAt == null) return '$who$uses · never expires';
    final left = DateTime.fromMillisecondsSinceEpoch(expiresAt).difference(now ?? DateTime.now());
    final when = left.inHours >= 48
        ? '${left.inDays} days'
        : left.inHours >= 1
        ? '${left.inHours} hours'
        : 'under an hour';
    return '$who$uses · expires in $when';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Invite people to ${widget.org.name}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_link),
        label: const Text('New link'),
      ),
      body: FutureBuilder(
        future: _invites,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton(onPressed: _reload, child: const Text('Couldn\'t load. Try again')),
            );
          }
          final invites = snapshot.data;
          if (invites == null) return const Center(child: CircularProgressIndicator());
          if (invites.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No invite links yet. Whoever opens one joins this organisation and sees its posts, chats and mini-apps.',
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
                  subtitle: Text(describe(invite)),
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

typedef _NewInvite = ({int? hours, int? uses, String? email});

/// How long a new link works, for how many people, and optionally for whose email only.
class _NewInviteSheet extends StatefulWidget {
  const _NewInviteSheet();

  @override
  State<_NewInviteSheet> createState() => _NewInviteSheetState();
}

class _NewInviteSheetState extends State<_NewInviteSheet> {
  int? _hours = 24 * 7;
  int? _uses;
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Works for', style: textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<int?>(
              segments: const [
                ButtonSegment(value: 24, label: Text('A day')),
                ButtonSegment(value: 24 * 7, label: Text('A week')),
                ButtonSegment(value: null, label: Text('Always')),
              ],
              selected: {_hours},
              onSelectionChanged: (s) => setState(() => _hours = s.first),
            ),
            const SizedBox(height: 16),
            Text('How many people', style: textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<int?>(
              segments: const [
                ButtonSegment(value: 1, label: Text('One')),
                ButtonSegment(value: 10, label: Text('Ten')),
                ButtonSegment(value: null, label: Text('Anyone')),
              ],
              selected: {_uses},
              onSelectionChanged: (s) => setState(() => _uses = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Only for this email (optional)',
                helperText: 'They must sign in with it, checked by the sign-in service.',
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  final email = _email.text.trim();
                  Navigator.of(context).pop((hours: _hours, uses: _uses, email: email.isEmpty ? null : email));
                },
                child: const Text('Make link'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
