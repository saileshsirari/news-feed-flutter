import 'package:geo_kit/geo_kit.dart';

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
    this.notifyEvents = false,
    this.area,
    this.distanceKm,
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
        notifyEvents: json['notifyEvents'] as bool? ?? false,
        area: json['area'] == null ? null : Place.fromJson(json['area'] as Map<String, dynamic>),
        distanceKm: (json['distanceKm'] as num?)?.toDouble(),
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

  /// You (a member) get a notification when a new event is planned here.
  final bool notifyEvents;

  /// Where it meets, roughly ("Indiranagar, Bengaluru", to about a km);
  /// null: anywhere.
  final Place? area;

  /// How far its area is from where you searched ("near me" lists only).
  final double? distanceKm;

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

/// An invite link's details, for its community's moderators.
class CommunityInvite {
  const CommunityInvite({required this.code, required this.uses, this.maxUses, this.expiresAt});

  factory CommunityInvite.fromJson(Map<String, dynamic> json) => CommunityInvite(
        code: json['code'] as String,
        uses: json['uses'] as int? ?? 0,
        maxUses: json['maxUses'] as int?,
        expiresAt: json['expiresAt'] as int?,
      );

  final String code;
  final int uses;

  /// Null: any number of people.
  final int? maxUses;

  /// Milliseconds since 1970; null: never expires.
  final int? expiresAt;

  /// The link people open. The app reads the code from it (see [codeFrom]).
  String link(Uri apiBase) => apiBase.replace(path: '/invite/$code').toString();

  /// The code in a pasted link or code: the last 10 letters and digits.
  static String? codeFrom(String text) =>
      RegExp(r'([0-9A-Za-z]{10})\s*$').firstMatch(text.trim().replaceAll(RegExp(r'[/?#]+$'), ''))?.group(1);
}

/// What an invite leads to, before joining.
class InvitePreview {
  const InvitePreview({required this.community, required this.works, this.reason});

  factory InvitePreview.fromJson(Map<String, dynamic> json) => InvitePreview(
        community: Community.fromJson(json['community'] as Map<String, dynamic>),
        works: json['works'] as bool,
        reason: json['reason'] as String?,
      );

  final Community community;
  final bool works;

  /// Why not ("this invite has expired"), when it doesn't work.
  final String? reason;
}
