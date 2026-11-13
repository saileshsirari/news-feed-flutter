import '../models/models.dart';

/// The comments shown in one sheet, kept in reading order by path (each
/// comment, then its replies). Paths are plain ASCII made to sort right as
/// text, so a new reply goes in its place by a simple compare: no tree to
/// rebuild.
///
/// [root] is the comment whose thread this is ("Continue this thread"), or
/// null for the whole post. Only [levels] levels show; deeper replies are
/// counted on their parent, which links to them.
class CommentThread {
  CommentThread({this.root, this.levels = 3});

  final PostComment? root;
  final int levels;
  final _comments = <PostComment>[];

  List<PostComment> get comments => List.unmodifiable(_comments);

  int get baseDepth => root?.depth ?? 0;

  /// How far [comment] is indented in this sheet.
  int indentOf(PostComment comment) => comment.depth - baseDepth;

  /// Whether [comment]'s replies are too deep for this sheet ("Continue this thread").
  bool continuesElsewhere(PostComment comment) =>
      comment.replyCount > 0 && comment.depth - baseDepth >= levels - 1;

  bool contains(int commentId) => _comments.any((c) => c.id == commentId);

  /// A page from the server (already in order, after what's here).
  void addPage(List<PostComment> page) {
    for (final c in page) {
      if (!contains(c.id)) _comments.add(c);
    }
  }

  void clear() => _comments.clear();

  /// A comment that's new: yours, or arriving live. True if it shows here;
  /// false if it belongs out of view (under a comment not loaded, or deeper
  /// than shown), in which case only its parent's count moves.
  bool insert(PostComment comment) {
    if (contains(comment.id)) return true;
    final parentIndex = comment.parentId == null ? -1 : _comments.indexWhere((c) => c.id == comment.parentId);
    if (parentIndex >= 0) {
      final parent = _comments[parentIndex];
      _comments[parentIndex] = parent.copyWith(replyCount: parent.replyCount + 1);
    }
    final inThisThread = root == null || comment.path.startsWith('${root!.path}.');
    final parentShown = comment.parentId == null ? root == null : parentIndex >= 0;
    if (!inThisThread || !parentShown || comment.depth - baseDepth >= levels) return false;
    var at = _comments.indexWhere((c) => c.path.compareTo(comment.path) > 0);
    if (at < 0) at = _comments.length;
    _comments.insert(at, comment);
    return true;
  }

  /// A comment was deleted: kept as "[deleted]" if [blanked] (it has
  /// replies), otherwise gone, along with any "[deleted]" parent it leaves
  /// with no replies (the server does the same).
  void remove(int commentId, {required bool blanked}) {
    final index = _comments.indexWhere((c) => c.id == commentId);
    if (index < 0) return;
    if (blanked) {
      _comments[index] = _comments[index].copyWith(deleted: true);
      return;
    }
    var gone = _comments.removeAt(index);
    while (gone.parentId != null) {
      final p = _comments.indexWhere((c) => c.id == gone.parentId);
      if (p < 0) return;
      final parent = _comments[p].copyWith(replyCount: (_comments[p].replyCount - 1).clamp(0, 1 << 30));
      if (!parent.deleted || parent.replyCount > 0) {
        _comments[p] = parent;
        return;
      }
      gone = _comments.removeAt(p);
    }
  }
}
