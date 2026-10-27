import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import 'feed_view_model.dart';

/// Mirrors news-feed-android's FeedScreen.kt.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<FeedViewModel>();

    // Fired by the realtime socket path, not by a fresh network read itself —
    // see FeedViewModel's dismissFanoutMessage.
    if (vm.fanoutMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(vm.fanoutMessage!)));
        vm.dismissFanoutMessage();
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('News Feed'),
            Text(
              '@${vm.currentUsername} · ${vm.followerCount} followers',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: vm.refresh),
          IconButton(icon: const Icon(Icons.logout), onPressed: vm.logout),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showComposeDialog(context, vm),
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
                onTap: vm.refresh,
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
                            ? TextButton(onPressed: vm.loadMore, child: const Text('Load more'))
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

  void _showComposeDialog(BuildContext context, FeedViewModel vm) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => _ComposePostDialog(
        isPosting: vm.isPosting,
        controller: controller,
        onPost: (body) {
          vm.publishPost(body);
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
