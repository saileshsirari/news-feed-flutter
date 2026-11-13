import '../models/models.dart';

enum CommunityVisibility { public, private }

enum CommunityRole { owner, moderator, member }

/// active: a member. pending: asked to join a private one. banned: can't join.
enum MembershipStatus { active, pending, banned }

T? _enumOrNull<T extends Enum>(List<T> values, Object? name) =>
    name is String ? values.where((v) => v.name == name).firstOrNull : null;

/// A community as the signed-in user sees it (with their role in it).
class Community {
  const Community({
    required this.id,
    required this.slug,
    required this.name,
    required this.visibility,
    required this.memberCount,
    this.description,
    this.photo,
    this.myRole,
    this.myStatus,
  });

  factory Community.fromJson(Map<String, dynamic> json) => Community(
        id: json['id'] as int,
        slug: json['slug'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        visibility: CommunityVisibility.values.byName(json['visibility'] as String),
        photo: ProfilePhoto.fromJson(json['photo']),
        memberCount: json['memberCount'] as int? ?? 0,
        myRole: _enumOrNull(CommunityRole.values, json['myRole']),
        myStatus: _enumOrNull(MembershipStatus.values, json['myStatus']),
      );

  final int id;

  /// For links: made from the name, never changes.
  final String slug;
  final String name;
  final String? description;
  final CommunityVisibility visibility;
  final ProfilePhoto? photo;
  final int memberCount;
  final CommunityRole? myRole;
  final MembershipStatus? myStatus;

  bool get isPrivate => visibility == CommunityVisibility.private;
  bool get isMember => myStatus == MembershipStatus.active;
  bool get isOwner => isMember && myRole == CommunityRole.owner;

  /// Owner or moderator: can approve, remove and ban.
  bool get canModerate => isMember && (myRole == CommunityRole.owner || myRole == CommunityRole.moderator);
}

/// One person in a community's member list (or join requests, or bans).
class CommunityMember {
  const CommunityMember({required this.user, required this.role, required this.status, required this.joinedAt});

  factory CommunityMember.fromJson(Map<String, dynamic> json) => CommunityMember(
        user: User.fromJson(json['user'] as Map<String, dynamic>),
        role: CommunityRole.values.byName(json['role'] as String),
        status: MembershipStatus.values.byName(json['status'] as String),
        joinedAt: json['joinedAt'] as int,
      );

  final User user;
  final CommunityRole role;
  final MembershipStatus status;
  final int joinedAt;
}

/// A page of results and where the next one starts (null: no more).
typedef CommunityPage<T> = ({List<T> items, String? nextCursor});
