import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/service_providers.dart';
import '../models/models.dart';
import '../session/current_user_provider.dart';
import '../data/paged_list.dart';
import 'communities_api.dart';
import 'community.dart';

/// Discovery: biggest first, or matching a search ('' for none).
class DiscoverNotifier extends AsyncNotifier<PagedList<Community>> with Paging<Community> {
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
class JoinedNotifier extends AsyncNotifier<PagedList<Community>> with Paging<Community> {
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
    // Your list of communities changed too, and which posts you can see here.
    ref.invalidate(joinedCommunitiesProvider);
    ref.invalidate(communityPostsProvider(id));
  }
}

final communityProvider =
    AsyncNotifierProvider.autoDispose.family<CommunityNotifier, Community, int>(CommunityNotifier.new);

/// A community's members, join requests or bans.
class MembersNotifier extends AsyncNotifier<PagedList<CommunityMember>> with Paging<CommunityMember> {
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

/// A community's posts, newest first, with what members can do to them.
class CommunityPostsNotifier extends AsyncNotifier<PagedList<Post>> with Paging<Post> {
  CommunityPostsNotifier(this.communityId);
  final int communityId;

  int get _me => ref.read(currentUserProvider).requireValue!.id;

  @override
  Future<CommunityPage<Post>> fetch(String? cursor) async {
    final page = await ref.read(communitiesApiProvider).posts(communityId, cursor: cursor);
    return (items: page.posts, nextCursor: page.nextCursor);
  }

  @override
  Future<PagedList<Post>> build() {
    ref.watch(communitiesApiProvider);
    return firstPage();
  }

  /// Posts in this community; shown at the top straight away.
  Future<void> publish(String body, List<int> mediaIds) async {
    final response = await ref
        .read(apiServiceProvider)
        .createPost(authorId: _me, body: body.trim(), mediaIds: mediaIds, communityId: communityId);
    if (ref.mounted) edit((items) => [response.post, ...items]);
  }

  Future<void> toggleLike(int postId) async {
    final before = _find(postId);
    if (before == null) return;
    final liked = !before.likedByMe;
    _replace(before.copyWith(likedByMe: liked, likeCount: (before.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 30)));
    try {
      final count = await ref.read(apiServiceProvider).likePost(postId, userId: _me, liked: liked);
      final now = _find(postId);
      if (ref.mounted && now != null) _replace(now.copyWith(likeCount: count));
    } catch (_) {
      if (ref.mounted) _replace(before);
    }
  }

  void setCommentCount(int postId, int count) {
    final post = _find(postId);
    if (post != null) _replace(post.copyWith(commentCount: count));
  }

  /// Yours, or (moderators) anyone's.
  Future<void> delete(int postId) async {
    await ref.read(apiServiceProvider).deletePost(postId, userId: _me);
    if (ref.mounted) edit((items) => [for (final p in items) if (p.id != postId) p]);
  }

  Post? _find(int postId) => state.value?.items.where((p) => p.id == postId).firstOrNull;
  void _replace(Post post) => edit((items) => [for (final p in items) p.id == post.id ? post : p]);
}

final communityPostsProvider =
    AsyncNotifierProvider.autoDispose.family<CommunityPostsNotifier, PagedList<Post>, int>(CommunityPostsNotifier.new);
