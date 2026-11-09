import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/service_providers.dart';
import '../models/models.dart';
import '../session/current_user_provider.dart';
import 'feed_notifier.dart';

/// A post's comments, oldest first, with a box to add one. You can delete
/// your own comments, and any comment on your own post.
Future<void> showComments(BuildContext context, Post post) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.85, child: CommentsSheet(post: post)),
    );

class CommentsSheet extends ConsumerStatefulWidget {
  const CommentsSheet({super.key, required this.post});
  final Post post;

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  final _input = TextEditingController();
  final _comments = <PostComment>[];
  String? _nextCursor;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  late int _count = widget.post.commentCount;

  int get _me => ref.read(currentUserProvider).requireValue!.id;

  @override
  void initState() {
    super.initState();
    _load();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(apiServiceProvider)
          .getComments(widget.post.id, _me, cursor: more ? _nextCursor : null);
      if (!mounted) return;
      setState(() {
        if (!more) _comments.clear();
        _comments.addAll(page.comments);
        _nextCursor = page.nextCursor;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Couldn\'t load comments: $e';
        });
      }
    }
  }

  void _setCount(int count) {
    _count = count;
    ref.read(feedProvider.notifier).setCommentCount(widget.post.id, count);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final comment = await ref.read(apiServiceProvider).addComment(widget.post.id, userId: _me, body: text);
      if (!mounted) return;
      _input.clear();
      setState(() {
        _comments.add(comment);
        _sending = false;
        _error = null;
      });
      _setCount(_count + 1);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Couldn\'t comment: $e';
        });
      }
    }
  }

  Future<void> _delete(PostComment comment) async {
    try {
      await ref.read(apiServiceProvider).deleteComment(widget.post.id, comment.id, userId: _me);
      if (!mounted) return;
      setState(() => _comments.removeWhere((c) => c.id == comment.id));
      _setCount((_count - 1).clamp(0, 1 << 30));
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t delete: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.post.authorId == _me;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Comments', style: Theme.of(context).textTheme.titleMedium),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Expanded(
          child: _loading && _comments.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _comments.isEmpty
                  ? const Center(child: Text('No comments yet. Be the first.'))
                  : ListView.builder(
                      itemCount: _comments.length + (_nextCursor != null ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == _comments.length) {
                          return TextButton(
                            onPressed: _loading ? null : () => _load(more: true),
                            child: const Text('Load more'),
                          );
                        }
                        final c = _comments[i];
                        return ListTile(
                          title: Text('@${c.authorUsername}', style: Theme.of(context).textTheme.labelLarge),
                          subtitle: Text(c.body),
                          trailing: c.authorId == _me || mine
                              ? IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Delete comment',
                                  onPressed: () => _delete(c),
                                )
                              : null,
                        );
                      },
                    ),
        ),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + MediaQuery.of(context).viewInsets.bottom),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('comment-input'),
                    controller: _input,
                    maxLength: 2000,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Add a comment',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  tooltip: 'Post comment',
                  onPressed: _input.text.trim().isEmpty || _sending ? null : _send,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
