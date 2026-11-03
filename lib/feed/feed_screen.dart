import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_media/shared_media.dart';
import '../models/models.dart';
import '../session/current_user_provider.dart';
import '../settings/settings_screen.dart';
import 'feed_notifier.dart';

enum _MenuAction { settings, logout }

/// The feed's own rule for how many files a post may carry (the server's
/// MAX_MEDIA_PER_POST); one draft for the compose dialog.
const _composeDraft = (id: 'feed', maxItems: 10);

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
              _MenuAction.settings => SettingsScreen.open(context),
              _MenuAction.logout => ref.read(currentUserProvider.notifier).logout(),
            },
            itemBuilder: (_) => const [
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
        onPressed: () => _showComposeDialog(context, vm, notifier),
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
                if (index < vm.posts.length) return _PostRow(vm.posts[index]);
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

  void _showComposeDialog(BuildContext context, FeedState vm, FeedNotifier notifier) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => _ComposePostDialog(
        isPosting: vm.isPosting,
        controller: controller,
        onPost: (body, mediaIds) {
          notifier.publishPost(body, mediaIds: mediaIds);
          Navigator.of(dialogContext).pop();
        },
      ),
    );
  }
}

class _PostRow extends StatelessWidget {
  final Post post;
  const _PostRow(this.post);

  @override
  Widget build(BuildContext context) {
    final time = DateTime.fromMillisecondsSinceEpoch(post.createdAt);
    final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('@${post.authorUsername}', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: 8),
              Text(timeStr, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          if (post.body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(post.body)),
          if (post.media.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: MediaGrid(media: post.media)),
        ],
      ),
    );
  }
}

class _ComposePostDialog extends ConsumerStatefulWidget {
  final bool isPosting;
  final TextEditingController controller;
  final void Function(String body, List<int> mediaIds) onPost;

  const _ComposePostDialog({required this.isPosting, required this.controller, required this.onPost});

  @override
  ConsumerState<_ComposePostDialog> createState() => _ComposePostDialogState();
}

class _ComposePostDialogState extends ConsumerState<_ComposePostDialog> {
  @override
  Widget build(BuildContext context) {
    // Watching keeps the draft alive while the dialog is open; closing the
    // dialog (posting or cancelling) disposes it.
    final draft = ref.watch(mediaDraftProvider(_composeDraft));
    final mediaIds = draft.mediaIds; // null while anything is uploading or failed
    final hasContent = widget.controller.text.trim().isNotEmpty || draft.items.isNotEmpty;

    return AlertDialog(
      title: const Text('New post'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: widget.controller,
            maxLines: 4,
            decoration: const InputDecoration(labelText: "What's happening?", border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          const ComposerAttachments(draftKey: _composeDraft),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Watch the snackbar after posting — that\'s the fanout cost.'),
          ),
        ],
      ),
      actions: [
        const AddMediaButton(draftKey: _composeDraft),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: widget.isPosting || !hasContent || mediaIds == null
              ? null
              : () => widget.onPost(widget.controller.text, mediaIds),
          child: Text(widget.isPosting
              ? 'Posting…'
              : draft.isPreparing
                  ? 'Compressing…'
                  : draft.isUploading
                      ? 'Uploading…'
                      : 'Post'),
        ),
      ],
    );
  }
}
