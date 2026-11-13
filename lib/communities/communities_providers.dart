import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'communities_api.dart';
import 'community.dart';

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
mixin _Paging<T> on AsyncNotifier<PagedList<T>> {
  Future<CommunityPage<T>> fetch(String? cursor);

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

/// Discovery: biggest first, or matching a search ('' for none).
class DiscoverNotifier extends AsyncNotifier<PagedList<Community>> with _Paging<Community> {
  DiscoverNotifier(this.query);
  final String query;

  @override
  Future<CommunityPage<Community>> fetch(String? cursor) =>
      ref.read(communitiesApiProvider).discover(query: query.isEmpty ? null : query, cursor: cursor);

  @override
  Future<PagedList<Community>> build() {
    ref.watch(communitiesApiProvider);
    return firstPage();
  }
}

final discoverCommunitiesProvider =
    AsyncNotifierProvider.autoDispose.family<DiscoverNotifier, PagedList<Community>, String>(DiscoverNotifier.new);

/// The communities you're in.
class JoinedNotifier extends AsyncNotifier<PagedList<Community>> with _Paging<Community> {
  @override
  Future<CommunityPage<Community>> fetch(String? cursor) => ref.read(communitiesApiProvider).joined(cursor: cursor);

  @override
  Future<PagedList<Community>> build() {
    ref.watch(communitiesApiProvider);
    return firstPage();
  }
}

final joinedCommunitiesProvider =
    AsyncNotifierProvider.autoDispose<JoinedNotifier, PagedList<Community>>(JoinedNotifier.new);

/// One community, and what you can do to it.
class CommunityNotifier extends AsyncNotifier<Community> {
  CommunityNotifier(this.id);
  final int id;

  CommunitiesApi get _api => ref.read(communitiesApiProvider);

  @override
  Future<Community> build() => ref.watch(communitiesApiProvider).get(id);

  Future<void> join() => _apply(() => _api.join(id));
  Future<void> leave() => _apply(() => _api.leave(id));

  /// After an edit or a membership change made elsewhere.
  void show(Community community) => state = AsyncData(community);

  Future<void> _apply(Future<Community> Function() action) async {
    final updated = await action();
    if (!ref.mounted) return;
    state = AsyncData(updated);
    // Your list of communities changed too.
    ref.invalidate(joinedCommunitiesProvider);
  }
}

final communityProvider =
    AsyncNotifierProvider.autoDispose.family<CommunityNotifier, Community, int>(CommunityNotifier.new);

/// A community's members, join requests or bans.
class MembersNotifier extends AsyncNotifier<PagedList<CommunityMember>> with _Paging<CommunityMember> {
  MembersNotifier(this.key);
  final ({int communityId, MembershipStatus status}) key;

  CommunitiesApi get _api => ref.read(communitiesApiProvider);

  @override
  Future<CommunityPage<CommunityMember>> fetch(String? cursor) =>
      _api.members(key.communityId, status: key.status, cursor: cursor);

  @override
  Future<PagedList<CommunityMember>> build() {
    ref.watch(communitiesApiProvider);
    return firstPage();
  }

  /// A join request accepted: off this list, onto the members list.
  Future<void> approve(int userId) async {
    await _api.approve(key.communityId, userId);
    _drop(userId);
    _refreshOthers();
  }

  /// Removed (a member), declined (a request) or unbanned (a ban); with [ban], banned.
  Future<void> remove(int userId, {bool ban = false}) async {
    await _api.removeMember(key.communityId, userId, ban: ban);
    _drop(userId);
    _refreshOthers();
  }

  Future<void> setRole(int userId, CommunityRole role) async {
    await _api.setRole(key.communityId, userId, role);
    // The list is sorted by role: load it again.
    ref.invalidateSelf();
  }

  void _drop(int userId) => edit((items) => [for (final m in items) if (m.user.id != userId) m]);

  /// The other lists and the member count moved too.
  void _refreshOthers() {
    for (final status in MembershipStatus.values) {
      if (status != key.status) ref.invalidate(communityMembersProvider((communityId: key.communityId, status: status)));
    }
    ref.invalidate(communityProvider(key.communityId));
  }
}

final communityMembersProvider = AsyncNotifierProvider.autoDispose
    .family<MembersNotifier, PagedList<CommunityMember>, ({int communityId, MembershipStatus status})>(
  MembersNotifier.new,
);
