import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/api_service.dart' show ApiException;
import 'org.dart';
import 'org_switcher.dart' show OrgLogo;
import 'orgs_controller.dart';

/// "Join with an invite": paste the link someone sent (or just its code),
/// see which organisation it's for, then join it and switch to it.
Future<void> showJoinOrg(BuildContext context, {String? link}) => showDialog<void>(
  context: context,
  builder: (_) => JoinOrgDialog(initialLink: link),
);

class JoinOrgDialog extends ConsumerStatefulWidget {
  const JoinOrgDialog({super.key, this.initialLink});

  final String? initialLink;

  @override
  ConsumerState<JoinOrgDialog> createState() => _JoinOrgDialogState();
}

class _JoinOrgDialogState extends ConsumerState<JoinOrgDialog> {
  late final _link = TextEditingController(text: widget.initialLink);
  OrgInvitePreview? _preview;
  String? _code;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  /// The server's own words for why, when it gave any ("this invite has expired").
  static String? _reason(ApiException e) {
    try {
      return (jsonDecode(e.body) as Map<String, dynamic>)['error'] as String?;
    } on Object {
      return null;
    }
  }

  Future<void> _look() async {
    final code = OrgInvite.codeFrom(_link.text);
    if (code == null) return setState(() => _error = 'That doesn\'t look like an organisation invite link.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await ref.read(orgsProvider.notifier).previewInvite(code);
      if (mounted) {
        setState(() {
          _preview = preview;
          _code = code;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.statusCode == 404 ? 'This invite link doesn\'t exist.' : 'Couldn\'t check it.');
      }
    } on Object {
      if (mounted) setState(() => _error = 'Couldn\'t check it. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      final org = await ref.read(orgsProvider.notifier).join(_code!);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('You\'re in ${org.name}')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _reason(e) ?? 'Couldn\'t join. Try again.');
    } on Object {
      if (mounted) setState(() => _error = 'Couldn\'t join. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final alreadyIn = preview?.org.myRole != null;
    return AlertDialog(
      title: Text(preview == null ? 'Join an organisation' : 'Join ${preview.org.name}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (preview == null)
            TextField(
              controller: _link,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Invite link or code'),
              onSubmitted: (_) => _look(),
            )
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: OrgLogo(org: preview.org),
              title: Text(preview.org.name),
              subtitle: Text(
                alreadyIn
                    ? 'You\'re already in it.'
                    : preview.usable
                    ? 'You\'ll see its posts, chats and mini-apps when it\'s the one picked at the top of Home.'
                    : 'This invite no longer works: ${preview.problem ?? 'ask for a new one'}.',
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
        if (preview == null)
          FilledButton(onPressed: _busy ? null : _look, child: const Text('Next'))
        else if (alreadyIn)
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(orgsProvider.notifier).switchTo(preview.org.id);
            },
            child: const Text('Switch to it'),
          )
        else
          FilledButton(onPressed: _busy || !preview.usable ? null : _join, child: const Text('Join')),
      ],
    );
  }
}
