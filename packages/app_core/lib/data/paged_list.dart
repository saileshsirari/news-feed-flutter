import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A list that loads a page at a time.
class PagedList<T> {
  const PagedList({this.items = const [], this.nextCursor, this.isLoadingMore = false});

  final List<T> items;
  final String? nextCursor;
  final bool isLoadingMore;

  bool get hasMore => nextCursor != null;

  PagedList<T> copyWith({List<T>? items, String? Function()? nextCursor, bool? isLoadingMore}) => PagedList(
        items: items ?? this.items,
        nextCursor: nextCursor != null ? nextCursor() : this.nextCursor,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      );
}

/// Shared paging: [fetch] gets a page from a cursor (null: the first).
mixin Paging<T> on AsyncNotifier<PagedList<T>> {
  Future<({List<T> items, String? nextCursor})> fetch(String? cursor);

  Future<PagedList<T>> firstPage() async {
    final page = await fetch(null);
    return PagedList(items: page.items, nextCursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.isLoadingMore) return;
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final page = await fetch(current.nextCursor);
      if (!ref.mounted) return;
      state = AsyncData(PagedList(items: [...current.items, ...page.items], nextCursor: page.nextCursor));
    } catch (_) {
      if (ref.mounted) state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }

  /// Applies [change] to the loaded items (a join, a removed member) without a reload.
  void edit(List<T> Function(List<T> items) change) {
    final current = state.value;
    if (current != null) state = AsyncData(current.copyWith(items: change(current.items)));
  }
}
