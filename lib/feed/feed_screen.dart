import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../session/current_user_provider.dart';
import '../settings/settings_screen.dart';
import 'feed_notifier.dart';
import 'compose_post_dialog.dart';
import 'post_card.dart';
import '../profile/profile_screen.dart';

enum _MenuAction { profile, settings, logout }

/// The feed's own rule for how many files a post may carry (the server's
/// MAX_MEDIA_PER_POST); one draft for the compose dialog.
const _composeDraft = (id: 'feed', maxItems: 10, sealed: false);

/// Mirrors news-feed-android's FeedScreen.kt.
///
/// Compose/Android: ≈ collecting `hiltViewModel<FeedViewModel>()`'s state;
/// `vm` below is the state, `notifier` the ViewModel you call methods on.
class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.watch(feedProvider);
    final notifier = ref.read(feedProvider.notifier);

    // A one-off side effect (show a snackbar), not something to draw, so
    // listen instead of watch: the callback runs once per change, outside
    // build. ≈ `LaunchedEffect(state.fanoutMessage) { snackbarHost.show(...) }`.
    // Replaces the old "check in build, then addPostFrameCallback" dance.
    ref.listen(feedProvider.select((s) => s.fanoutMessage), (_, message) {
      if (message == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      notifier.dismissFanoutMessage();
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('News Feed'),
            Text(
              '@${vm.user.username} · ${vm.user.followerCount} followers',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: notifier.refresh),
          PopupMenuButton<_MenuAction>(
            onSelected: (action) => switch (action) {
              _MenuAction.profile => ProfileScreen.open(context, vm.user.id),
              _MenuAction.settings => SettingsScreen.open(context),
              _MenuAction.logout => ref.read(currentUserProvider.notifier).logout(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _MenuAction.profile,
                child: ListTile(leading: Icon(Icons.person_outline), title: Text('My profile')),
              ),
              PopupMenuItem(
                value: _MenuAction.settings,
                child: ListTile(leading: Icon(Icons.settings_outlined), title: Text('Settings')),
              ),
              PopupMenuItem(
                value: _MenuAction.logout,
                child: ListTile(leading: Icon(Icons.logout), title: Text('Log out')),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: vm.isPosting
            ? null
            : () => showComposePostDialog(
                  context,
                  draftKey: _composeDraft,
                  hint: 'Watch the snackbar after posting — that\'s the fanout cost.',
                  onPost: (body, mediaIds) => notifier.publishPost(body, mediaIds: mediaIds),
                ),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          if (vm.error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(vm.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (vm.hasNewPosts)
            Material(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: InkWell(
                onTap: notifier.refresh,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'New posts available — tap to refresh',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                ),
              ),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: vm.posts.length + 1,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index < vm.posts.length) {
                  final post = vm.posts[index];
                  return PostCard(
                    post,
                    onLike: () => notifier.toggleLike(post.id),
                    onCommentCount: (count) => notifier.setCommentCount(post.id, count),
                    onDelete: () => notifier.deletePost(post.id),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: vm.isLoading
                        ? const CircularProgressIndicator()
                        : vm.nextCursor != null
                            ? TextButton(onPressed: notifier.loadMore, child: const Text('Load more'))
                            : vm.posts.isEmpty
                                ? const Text('No posts yet — follow someone or write one.')
                                : const SizedBox.shrink(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
