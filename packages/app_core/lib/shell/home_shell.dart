import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../inbox/inbox.dart';
import '../mini_app/app_links.dart';
import '../mini_app/mini_app.dart';
import '../mini_app/registry.dart';
import '../orgs/org_switcher.dart';
import '../orgs/orgs_controller.dart';
import '../push/local_notifications.dart';
import '../session/current_user_provider.dart';
import '../settings/settings_screen.dart';

/// Home: a grid of mini-app tiles, like a phone's home screen inside the
/// app, plus a small bar for what belongs to no one mini-app: your account,
/// the notifications inbox, and chat (messages reach you anywhere).
///
/// Only exists while someone is signed in (see SuperApp).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.title});

  final String title;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  StreamSubscription<Uri>? _taps;

  @override
  void initState() {
    super.initState();
    // A tapped notification opens what it's about (a chat, an event).
    _taps = notificationTaps.listen(_open);
    unawaited(
      launchNotificationLink().then((link) {
        if (link != null) _open(link);
      }),
    );
  }

  /// Opens a tapped notification's link; one about another organisation
  /// (`org=` in it) switches there first, so what it opens is in view.
  Future<void> _open(Uri link) async {
    final orgId = int.tryParse(link.queryParameters['org'] ?? '');
    if (orgId != null) await ref.read(orgsProvider.notifier).switchTo(orgId);
    if (mounted) openAppLink(context, link);
  }

  @override
  void dispose() {
    _taps?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final launcher = ref.watch(launcherSlotsProvider);
    final slots = launcher.value ?? const <MiniAppSlot>[];
    final chat = [
      for (final s in slots)
        if (s.info.isGlobal) s,
    ];

    return Scaffold(
      appBar: AppBar(
        // The organisation shown (tap to switch, join or invite), like a Slack workspace's name.
        title: OrgTitle(fallback: widget.title),
        actions: [
          for (final slot in chat)
            IconButton(
              tooltip: slot.info.name,
              icon: _Badged(slot: slot, child: Icon(slot.info.icon)),
              onPressed: () => openMiniApp(context, slot),
            ),
          const _InboxButton(),
          const _AccountMenu(),
        ],
      ),
      body: switch (launcher) {
        AsyncData() when slots.isEmpty => const Center(child: Text('Nothing to show here yet.')),
        AsyncData() => _Grid(slots: slots),
        // The provider never fails (it falls back to every mini-app), so this is loading.
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// Opens [slot]'s mini-app full screen. On the web its code may need
/// downloading first (a deferred import), so there's a moment of spinner.
Future<void> openMiniApp(BuildContext context, MiniAppSlot slot) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MiniAppHost(slot: slot)));

/// A mini-app's home screen, once its code is loaded. Its own screens push
/// on top; the back arrow on its home returns to the Home grid.
class MiniAppHost extends StatefulWidget {
  const MiniAppHost({super.key, required this.slot});

  final MiniAppSlot slot;

  @override
  State<MiniAppHost> createState() => _MiniAppHostState();
}

class _MiniAppHostState extends State<MiniAppHost> {
  late Future<MiniApp> _app = widget.slot.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<MiniApp>(
    future: _app,
    initialData: widget.slot.loaded,
    builder: (context, snapshot) {
      final app = snapshot.data;
      if (app != null) return app.buildHome(context);
      return Scaffold(
        appBar: AppBar(title: Text(widget.slot.info.name)),
        body: Center(
          child: snapshot.hasError
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Couldn\'t open ${widget.slot.info.name}.'),
                    TextButton(
                      onPressed: () => setState(() => _app = widget.slot.load()),
                      child: const Text('Try again'),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}

class _Grid extends StatelessWidget {
  const _Grid({required this.slots});

  final List<MiniAppSlot> slots;

  @override
  Widget build(BuildContext context) => GridView.extent(
    maxCrossAxisExtent: 140,
    padding: const EdgeInsets.all(16),
    mainAxisSpacing: 16,
    crossAxisSpacing: 16,
    children: [for (final slot in slots) MiniAppTile(slot: slot)],
  );
}

/// One mini-app on the grid: its icon on its colour, and its name.
class MiniAppTile extends StatelessWidget {
  const MiniAppTile({super.key, required this.slot});

  final MiniAppSlot slot;

  @override
  Widget build(BuildContext context) {
    final info = slot.info;
    return InkWell(
      key: ValueKey('tile-${info.id}'),
      borderRadius: BorderRadius.circular(20),
      onTap: () => openMiniApp(context, slot),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Badged(
            slot: slot,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: info.color, borderRadius: BorderRadius.circular(18)),
              child: Icon(info.icon, color: Colors.white, size: 32),
            ),
          ),
          const SizedBox(height: 8),
          Text(info.name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// [child] with the mini-app's badge count, when it has one and it's loaded.
class _Badged extends ConsumerWidget {
  const _Badged({required this.slot, required this.child});

  final MiniAppSlot slot;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badge = slot.loaded?.badgeCount;
    final count = badge == null ? 0 : ref.watch(badge);
    return Badge(isLabelVisible: count > 0, label: Text('$count'), child: child);
  }
}

class _InboxButton extends ConsumerWidget {
  const _InboxButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unseen = ref.watch(inboxProvider.select((s) => s.unseen));
    return IconButton(
      tooltip: 'Notifications',
      icon: Badge(isLabelVisible: unseen > 0, label: Text('$unseen'), child: const Icon(Icons.notifications_outlined)),
      onPressed: () => InboxScreen.open(context),
    );
  }
}

enum _AccountAction { profile, settings, logout }

class _AccountMenu extends ConsumerWidget {
  const _AccountMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    if (user == null) return const SizedBox.shrink();
    // Profiles live in the feed mini-app; no feed in this build, no link.
    final hasProfiles = slotFor(ref.watch(miniAppSlotsProvider), 'feed') != null;
    return PopupMenuButton<_AccountAction>(
      tooltip: 'Account',
      icon: CircleAvatar(radius: 14, child: Text(user.username.isEmpty ? '?' : user.username[0].toUpperCase())),
      onSelected: (action) => switch (action) {
        _AccountAction.profile => openAppLink(context, AppLinks.profile(user.id)),
        _AccountAction.settings => SettingsScreen.open(context),
        _AccountAction.logout => ref.read(currentUserProvider.notifier).logout(),
      },
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, child: Text('@${user.username}')),
        if (hasProfiles)
          const PopupMenuItem(
            value: _AccountAction.profile,
            child: ListTile(leading: Icon(Icons.person_outline), title: Text('My profile')),
          ),
        const PopupMenuItem(
          value: _AccountAction.settings,
          child: ListTile(leading: Icon(Icons.settings_outlined), title: Text('Settings')),
        ),
        const PopupMenuItem(
          value: _AccountAction.logout,
          child: ListTile(leading: Icon(Icons.logout), title: Text('Log out')),
        ),
      ],
    );
  }
}
