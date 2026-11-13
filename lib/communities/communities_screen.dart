import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../profile/user_avatar.dart';
import 'communities_providers.dart';
import 'community.dart';
import 'community_screen.dart';
import 'edit_community_screen.dart';
import 'join_with_invite.dart';
import '../events/event.dart';
import '../events/event_tile.dart';
import '../events/events_providers.dart';

/// The Communities tab: yours first, then the biggest ones to discover, or
/// search results while you type.
class CommunitiesScreen extends ConsumerStatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  ConsumerState<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends ConsumerState<CommunitiesScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// Searches once typing pauses, not on every key.
  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = text.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final joined = _query.isEmpty ? ref.watch(joinedCommunitiesProvider) : null;
    final discover = ref.watch(discoverCommunitiesProvider(_query));
    final textTheme = Theme.of(context).textTheme;

    Widget header(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(title, style: textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
        );

    final yours = joined?.value?.items ?? const <Community>[];
    // Coming up across your communities (only while not searching).
    final upcoming = _query.isEmpty ? ref.watch(upcomingEventsProvider).value?.items ?? const <Event>[] : const <Event>[];
    final found = discover.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Communities'),
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Join with an invite',
            onPressed: () => showJoinWithInvite(context),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SearchBar(
              controller: _search,
              hintText: 'Search communities',
              leading: const Icon(Icons.search),
              onChanged: _onSearchChanged,
              elevation: const WidgetStatePropertyAll(0),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => EditCommunityScreen.create(context),
        icon: const Icon(Icons.add),
        label: const Text('Create'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(joinedCommunitiesProvider);
          ref.invalidate(upcomingEventsProvider);
          ref.invalidate(discoverCommunitiesProvider(_query));
          await ref.read(discoverCommunitiesProvider(_query).future);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            if (upcoming.isNotEmpty) ...[
              header('Upcoming events'),
              for (final e in upcoming.take(5)) EventTile(e, showCommunity: true),
            ],
            if (yours.isNotEmpty) ...[
              header('Your communities'),
              for (final c in yours) CommunityTile(c),
            ],
            header(_query.isEmpty ? 'Discover' : 'Results for "$_query"'),
            if (discover.hasError && found == null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text('Couldn\'t load communities.'),
                    TextButton(
                      onPressed: () => ref.invalidate(discoverCommunitiesProvider(_query)),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              )
            else if (found == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (found.items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _query.isEmpty ? 'No communities yet. Create the first one!' : 'Nothing matches "$_query".',
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              for (final c in found.items) CommunityTile(c),
              if (found.hasMore)
                Center(
                  child: found.isLoadingMore
                      ? const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())
                      : TextButton(
                          onPressed: () => ref.read(discoverCommunitiesProvider(_query).notifier).loadMore(),
                          child: const Text('Load more'),
                        ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One community in a list: photo, name, private or public, members, and your place in it.
class CommunityTile extends StatelessWidget {
  const CommunityTile(this.community, {super.key});

  final Community community;

  @override
  Widget build(BuildContext context) {
    final c = community;
    final role = switch ((c.myStatus, c.myRole)) {
      (MembershipStatus.active, CommunityRole.owner) => 'Owner',
      (MembershipStatus.active, CommunityRole.moderator) => 'Moderator',
      (MembershipStatus.active, _) => 'Joined',
      (MembershipStatus.pending, _) => 'Requested',
      _ => null,
    };
    return ListTile(
      leading: UserAvatar(name: c.name, photo: c.photo),
      title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${c.isPrivate ? 'Private' : 'Public'} · ${c.memberCount} ${c.memberCount == 1 ? 'member' : 'members'}',
      ),
      trailing: role == null ? null : Text(role, style: Theme.of(context).textTheme.labelMedium),
      onTap: () => CommunityScreen.open(context, c.id),
    );
  }
}
