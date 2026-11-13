import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/app_socket.dart';
import '../data/services/service_providers.dart';
import '../data/services/socket_provider.dart';
import '../models/models.dart';
import '../session/current_user_provider.dart';
import 'comment_thread.dart';
import 'feed_notifier.dart';

/// A post's comments as threads: each comment, then its replies, indented,
/// three levels deep (deeper ones open with "Continue this thread"). Reply
/// to any comment; delete your own, or any on your own post. New comments
/// from others arrive live while it's open. [onCountChanged] keeps the
/// count under the post right (by default, in the feed).
Future<void> showComments(
  BuildContext context,
  Post post, {
  ValueChanged<int>? onCountChanged,
  PostComment? thread,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: CommentsSheet(post: post, onCountChanged: onCountChanged, thread: thread),
      ),
    );

class CommentsSheet extends ConsumerStatefulWidget {
  const CommentsSheet({super.key, required this.post, this.onCountChanged, this.thread});
  final Post post;
  final ValueChanged<int>? onCountChanged;

  /// Set for "Continue this thread": just this comment and its replies.
  final PostComment? thread;

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  late final _thread = CommentThread(root: widget.thread);
  String? _nextCursor;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  late int _count = widget.post.commentCount;

  /// Who you're replying to (null: a comment on the post itself).
  PostComment? _replyTo;

  /// New comments that arrived live but didn't fit in the batch: "N new comments".
  int _unseen = 0;

  /// Changes already shown (your own, or ones that came twice), so the
  /// count moves once each.
  final _handled = <String>{};

  late final int _me = ref.read(currentUserProvider).requireValue!.id;
  StreamSubscription<Map<String, dynamic>>? _live;

  /// Kept from opening: providers can't be read once the sheet is closing.
  late final AppSocket _socket = ref.read(socketProvider(_me));

  @override
  void initState() {
    super.initState();
    _load();
    _input.addListener(() => setState(() {}));
    _socket.watchPost(widget.post.id);
    _live = _socket.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _live?.cancel();
    // The socket outlives the sheet; it still has to be told.
    _socket.unwatchPost(widget.post.id);
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() => _loading = true);
    try {
      final page = await ref.read(apiServiceProvider).getComments(
            widget.post.id,
            _me,
            cursor: more ? _nextCursor : null,
            under: widget.thread?.id,
          );
      if (!mounted) return;
      setState(() {
        if (!more) {
          _thread.clear();
          _unseen = 0;
        }
        _thread.addPage(page.comments);
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

  /// A batch of live changes to this post's comments (at most one every 2 s).
  void _onEvent(Map<String, dynamic> event) {
    if (event['type'] != 'post_comments' || event['postId'] != widget.post.id || !mounted) return;
    var countChange = 0;
    final added = [for (final c in event['added'] as List? ?? const []) PostComment.fromJson(c as Map<String, dynamic>)];
    for (final comment in added) {
      if (!_handled.add('added:${comment.id}')) continue;
      countChange++;
      _thread.insert(comment);
    }
    // More arrived than the batch carries: counted, and offered to load.
    final overflow = (event['addedCount'] as int? ?? added.length) - added.length;
    countChange += overflow;
    for (final r in event['removed'] as List? ?? const []) {
      final id = (r as Map<String, dynamic>)['commentId'] as int;
      if (!_handled.add('removed:$id')) continue;
      countChange--;
      _thread.remove(id, blanked: r['blanked'] == true);
    }
    setState(() => _unseen += overflow);
    if (countChange != 0) _setCount((_count + countChange).clamp(0, 1 << 30));
  }

  void _setCount(int count) {
    _count = count;
    final onCountChanged = widget.onCountChanged;
    if (onCountChanged != null) {
      onCountChanged(count);
    } else {
      ref.read(feedProvider.notifier).setCommentCount(widget.post.id, count);
    }
  }

  void _startReply(PostComment comment) {
    setState(() => _replyTo = comment);
    _inputFocus.requestFocus();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final comment = await ref
          .read(apiServiceProvider)
          .addComment(widget.post.id, userId: _me, body: text, parentId: _replyTo?.id ?? widget.thread?.id);
      if (!mounted) return;
      _input.clear();
      _handled.add('added:${comment.id}');
      setState(() {
        _thread.insert(comment);
        _replyTo = null;
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
      _handled.add('removed:${comment.id}');
      // With replies it stays as "[deleted]" (the server does the same).
      setState(() => _thread.remove(comment.id, blanked: comment.replyCount > 0));
      _setCount((_count - 1).clamp(0, 1 << 30));
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t delete: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final comments = _thread.comments;
    final postIsMine = widget.post.authorId == _me;

    Widget row(PostComment c) {
      final canDelete = !c.deleted && (c.authorId == _me || postIsMine);
      final indent = _thread.indentOf(c);
      return Padding(
        key: ValueKey(c.id),
        padding: EdgeInsets.only(left: 16.0 + 20.0 * indent, right: 8, top: 6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: indent > 0 ? Border(left: BorderSide(color: colors.outlineVariant, width: 2)) : const Border(),
          ),
          child: Padding(
            padding: EdgeInsets.only(left: indent > 0 ? 10 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.deleted)
                  Text(
                    '[deleted]',
                    style: textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: colors.outline),
                  )
                else ...[
                  Text('@${c.authorUsername}', style: textTheme.labelLarge),
                  Text(c.body),
                ],
                Wrap(
                  children: [
                    if (!c.deleted)
                      TextButton(
                        key: Key('reply-${c.id}'),
                        onPressed: () => _startReply(c),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        child: const Text('Reply'),
                      ),
                    if (canDelete)
                      TextButton(
                        onPressed: () => _delete(c),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        child: const Text('Delete'),
                      ),
                    if (_thread.continuesElsewhere(c))
                      TextButton(
                        key: Key('continue-${c.id}'),
                        // Its own sheet, from this comment down.
                        onPressed: () => showComments(context, widget.post, onCountChanged: _setCount, thread: c),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        child: Text('Continue this thread (${c.replyCount}) →'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(widget.thread == null ? 'Comments' : 'Thread', style: textTheme.titleMedium),
        ),
        if (_unseen > 0)
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.arrow_upward, size: 16),
            label: Text('$_unseen new ${_unseen == 1 ? 'comment' : 'comments'}'),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: TextStyle(color: colors.error)),
          ),
        Expanded(
          child: _loading && comments.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : comments.isEmpty
                  ? const Center(child: Text('No comments yet. Be the first.'))
                  : ListView.builder(
                      itemCount: comments.length + (_nextCursor != null ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == comments.length) {
                          return TextButton(
                            onPressed: _loading ? null : () => _load(more: true),
                            child: const Text('Load more'),
                          );
                        }
                        return row(comments[i]);
                      },
                    ),
        ),
        if (_replyTo != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
            child: Row(
              children: [
                Expanded(child: Text('Replying to @${_replyTo!.authorUsername}', style: textTheme.labelMedium)),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Cancel reply',
                  onPressed: () => setState(() => _replyTo = null),
                ),
              ],
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
                    focusNode: _inputFocus,
                    maxLength: 2000,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: _replyTo != null || widget.thread != null ? 'Add a reply' : 'Add a comment',
                      border: const OutlineInputBorder(),
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
