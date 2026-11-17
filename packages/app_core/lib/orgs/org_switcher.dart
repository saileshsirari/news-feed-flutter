import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'join_org_dialog.dart';
import 'org.dart';
import 'org_invites_screen.dart';
import 'orgs_controller.dart';

/// The organisation's logo and name at the top of Home, as a button that
/// opens the switcher, like the workspace name at the top of Slack.
/// Shows [fallback] (the app's name) while loading, or with a server from
/// before organisations.
class OrgTitle extends ConsumerWidget {
  const OrgTitle({super.key, required this.fallback});

  final String fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(orgsProvider.select((orgs) => orgs.value?.current));
    if (org == null) return Text(fallback);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showOrgSwitcher(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OrgLogo(org: org, size: 28),
            const SizedBox(width: 10),
            Flexible(child: Text(org.name, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

/// An organisation's logo, or its first letter on a coloured square.
class OrgLogo extends StatelessWidget {
  const OrgLogo({super.key, required this.org, this.size = 40});

  final Org org;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = org.logoUrl;
    final letter = Text(
      org.name.isEmpty ? '?' : org.name.characters.first.toUpperCase(),
      style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold, fontSize: size * 0.45),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: SizedBox.square(
        dimension: size,
        child: url == null
            ? ColoredBox(
                color: scheme.primaryContainer,
                child: Center(child: letter),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: scheme.primaryContainer,
                  child: Center(child: letter),
                ),
              ),
      ),
    );
  }
}

/// My organisations: tap one to switch to it. Below them, joining another
/// with an invite, and (for owners and admins) inviting people.
Future<void> showOrgSwitcher(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => const _OrgSwitcherSheet(),
);

class _OrgSwitcherSheet extends ConsumerWidget {
  const _OrgSwitcherSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(orgsProvider).value ?? OrgsState.none;
    final current = state.current;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Your organisations', style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final org in state.orgs)
              ListTile(
                leading: OrgLogo(org: org),
                title: Text(org.name),
                subtitle: Text(_roleName(org.myRole)),
                trailing: org.id == state.currentId ? const Icon(Icons.check) : null,
                selected: org.id == state.currentId,
                onTap: () {
                  Navigator.of(context).pop();
                  ref.read(orgsProvider.notifier).switchTo(org.id);
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Join with an invite'),
              onTap: () {
                Navigator.of(context).pop();
                showJoinOrg(context);
              },
            ),
            if (current != null && current.canInvite)
              ListTile(
                leading: const Icon(Icons.person_add_alt),
                title: Text('Invite people to ${current.name}'),
                onTap: () {
                  Navigator.of(context).pop();
                  OrgInvitesScreen.open(context, current);
                },
              ),
          ],
        ),
      ),
    );
  }

  static String _roleName(String? role) => switch (role) {
    'owner' => 'Owner',
    'admin' => 'Admin',
    _ => 'Member',
  };
}
