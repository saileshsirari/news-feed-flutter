import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/service_providers.dart';
import '../data/services/socket_provider.dart';
import '../models/models.dart';
import '../session/current_user_provider.dart';
import 'comment_thread.dart';

/// Which comments a sheet shows: a post's, or ("Continue this thread") one
/// comment's thread on it. Equal by ids, so the same sheet finds the same state.
class CommentsKey {
  const CommentsKey(this.post, [this.thread]);

  final Post post;
  final PostComment? thread;

  @override
  bool operator ==(Object other) => other is CommentsKey && other.post.id == post.id && other.thread?.id == thread?.id;

  @override
  int get hashCode => Object.hash(post.id, thread?.id);
}

/// Everything a comments sheet draws.
class CommentsState {
  const CommentsState({
    required this.comments,
    required this.baseDepth,
    required this.count,
    this.levels = 3,
    this.nextCursor,
    this.isLoading = true,
    this.isSending = false,
    this.error,
    this.replyTo,
    this.unseen = 0,
  });

  /// In reading order (each comment, then its replies).
  final List<PostComment> comments;
  final int baseDepth;
  final int levels;

  /// The post's comment count, kept up to date (for the count under the post).
  final int count;
  final String? nextCursor;
  final bool isLoading;
  final bool isSending;
  final String? error;

  /// Who you're replying to (null: the post itself, or the thread's comment).
  final PostComment? replyTo;

  /// New comments that arrived live but didn't fit in a batch: "N new comments".
  final int unseen;

  /// How far [comment] is indented here.
  int indentOf(PostComment comment) => comment.depth - baseDepth;

  /// Whether [comment]'s replies are too deep for this sheet ("Continue this thread").
  bool continuesElsewhere(PostComment comment) => comment.replyCount > 0 && indentOf(comment) >= levels - 1;

  CommentsState copyWith({
    List<PostComment>? comments,
    int? count,
    String? Function()? nextCursor,
    bool? isLoading,
    bool? isSending,
    String? Function()? error,
    PostComment? Function()? replyTo,
    int? unseen,
  }) =>
      CommentsState(
        comments: comments ?? this.comments,
        baseDepth: baseDepth,
        levels: levels,
        count: count ?? this.count,
        nextCursor: nextCursor != null ? nextCursor() : this.nextCursor,
        isLoading: isLoading ?? this.isLoading,
        isSending: isSending ?? this.isSending,
        error: error != null ? error() : this.error,
        replyTo: replyTo != null ? replyTo() : this.replyTo,
        unseen: unseen ?? this.unseen,
      );
}

/// One comments sheet's logic (≈ its ViewModel): loading pages, live
/// changes, replying and deleting. While it's alive, the post is watched
/// over the socket, so others' comments arrive live; it stops when the
/// sheet closes (autoDispose).
class CommentsNotifier extends Notifier<CommentsState> {
  CommentsNotifier(this.key);
  final CommentsKey key;

  late CommentThread _thread;
  late int _me;

  /// Changes already shown (your own, or ones that came twice), so the
  /// count moves once each.
  final _handled = <String>{};

  @override
  CommentsState build() {
    _me = ref.read(currentUserProvider).requireValue!.id;
    _thread = CommentThread(root: key.thread);

    final socket = ref.read(socketProvider(_me));
    socket.watchPost(key.post.id);
    final live = socket.events.listen(_onEvent);
    ref.onDispose(() {
      live.cancel();
      socket.unwatchPost(key.post.id);
    });

    Future.microtask(load);
    return CommentsState(comments: const [], baseDepth: _thread.baseDepth, count: key.post.commentCount);
  }

  /// The first page (again), or with [more], the next one.
  Future<void> load({bool more = false}) async {
    state = state.copyWith(isLoading: true);
    try {
      final page = await ref.read(apiServiceProvider).getComments(
            key.post.id,
            _me,
            cursor: more ? state.nextCursor : null,
            under: key.thread?.id,
          );
      if (!ref.mounted) return;
      if (!more) _thread.clear();
      _thread.addPage(page.comments);
      state = state.copyWith(
        comments: _thread.comments,
        nextCursor: () => page.nextCursor,
        isLoading: false,
        error: () => null,
        unseen: more ? null : 0,
      );
    } catch (e) {
      if (ref.mounted) state = state.copyWith(isLoading: false, error: () => 'Couldn\'t load comments: $e');
    }
  }

  void startReply(PostComment comment) => state = state.copyWith(replyTo: () => comment);
  void cancelReply() => state = state.copyWith(replyTo: () => null);

  /// Posts [text] as a reply to [CommentsState.replyTo] (or the thread's
  /// comment, or the post). Shown as soon as the server has it. True if it went.
  Future<bool> send(String text) async {
    final body = text.trim();
    if (body.isEmpty || state.isSending) return false;
    state = state.copyWith(isSending: true);
    try {
      final comment = await ref
          .read(apiServiceProvider)
          .addComment(key.post.id, userId: _me, body: body, parentId: state.replyTo?.id ?? key.thread?.id);
      if (!ref.mounted) return true;
      // It comes back in the next live batch too: don't count it twice.
      _handled.add('added:${comment.id}');
      _thread.insert(comment);
      state = state.copyWith(
        comments: _thread.comments,
        count: state.count + 1,
        isSending: false,
        replyTo: () => null,
        error: () => null,
      );
      return true;
    } catch (e) {
      if (ref.mounted) state = state.copyWith(isSending: false, error: () => 'Couldn\'t comment: $e');
      return false;
    }
  }

  Future<void> delete(PostComment comment) async {
    try {
      await ref.read(apiServiceProvider).deleteComment(key.post.id, comment.id, userId: _me);
      if (!ref.mounted) return;
      _handled.add('removed:${comment.id}');
      // With replies it stays as "[deleted]" (the server does the same).
      _thread.remove(comment.id, blanked: comment.replyCount > 0);
      state = state.copyWith(comments: _thread.comments, count: (state.count - 1).clamp(0, 1 << 30));
    } catch (e) {
      if (ref.mounted) state = state.copyWith(error: () => 'Couldn\'t delete: $e');
    }
  }

  /// A batch of live changes to a post's comments (at most one every 2 s).
  void _onEvent(Map<String, dynamic> event) {
    if (event['type'] != 'post_comments' || event['postId'] != key.post.id || !ref.mounted) return;
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
    state = state.copyWith(
      comments: _thread.comments,
      count: (state.count + countChange).clamp(0, 1 << 30),
      unseen: state.unseen + overflow,
    );
  }
}

/// autoDispose: a sheet's state goes (and its post stops being watched) when it closes.
final commentsProvider =
    NotifierProvider.autoDispose.family<CommentsNotifier, CommentsState, CommentsKey>(CommentsNotifier.new);
