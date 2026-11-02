import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../session/current_user_provider.dart';
import 'feed_notifier.dart';

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
          IconButton(icon: const Icon(Icons.logout), onPressed: ref.read(currentUserProvider.notifier).logout),
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
        onPost: (body) {
          notifier.publishPost(body);
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
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(post.body)),
        ],
      ),
    );
  }
}

class _ComposePostDialog extends StatefulWidget {
  final bool isPosting;
  final TextEditingController controller;
  final ValueChanged<String> onPost;

  const _ComposePostDialog({required this.isPosting, required this.controller, required this.onPost});

  @override
  State<_ComposePostDialog> createState() => _ComposePostDialogState();
}

class _ComposePostDialogState extends State<_ComposePostDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New post'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: widget.controller,
            maxLines: 4,
            decoration: const InputDecoration(labelText: "What's happening?", border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Watch the snackbar after posting — that\'s the fanout cost.'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: widget.isPosting || widget.controller.text.trim().isEmpty
              ? null
              : () => widget.onPost(widget.controller.text),
          child: Text(widget.isPosting ? 'Posting…' : 'Post'),
        ),
      ],
    );
  }
}
