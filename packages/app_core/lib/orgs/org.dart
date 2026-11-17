import 'package:flutter/foundation.dart';

/// An organisation, like a Slack workspace: a business client's own space,
/// whose people see only its posts, chats, communities and rides. Everyone
/// is in at least one; "Beautiful Apps" is the open, everyone's one.
@immutable
class Org {
  const Org({required this.id, required this.slug, required this.name, this.logoUrl, this.myRole});

  factory Org.fromJson(Map<String, dynamic> json) => Org(
    id: json['id'] as int,
    slug: json['slug'] as String,
    name: json['name'] as String,
    logoUrl: (json['logo'] as Map<String, dynamic>?)?['url'] as String?,
    myRole: json['myRole'] as String?,
  );

  final int id;
  final String slug;
  final String name;
  final String? logoUrl;

  /// "owner", "admin" or "member"; null if I'm not in it (an invite's preview).
  final String? myRole;

  /// Owners and admins can invite people.
  bool get canInvite => myRole == 'owner' || myRole == 'admin';

  @override
  bool operator ==(Object other) =>
      other is Org &&
      other.id == id &&
      other.slug == slug &&
      other.name == name &&
      other.logoUrl == logoUrl &&
      other.myRole == myRole;

  @override
  int get hashCode => Object.hash(id, slug, name, logoUrl, myRole);
}

/// A link that lets people into an organisation.
@immutable
class OrgInvite {
  const OrgInvite({
    required this.code,
    required this.role,
    required this.uses,
    this.email,
    this.expiresAt,
    this.maxUses,
  });

  factory OrgInvite.fromJson(Map<String, dynamic> json) => OrgInvite(
    code: json['code'] as String,
    role: json['role'] as String,
    email: json['email'] as String?,
    expiresAt: json['expiresAt'] as int?,
    maxUses: json['maxUses'] as int?,
    uses: json['uses'] as int,
  );

  final String code;
  final String role;

  /// Only someone signed in with this email may use it; null: anyone with the link.
  final String? email;
  final int? expiresAt;
  final int? maxUses;
  final int uses;

  /// The link people open: `<server>/join/<code>`. The app reads the code from it ([codeFrom]).
  String link(Uri apiBase) => apiBase.replace(path: '/join/$code').toString();

  /// The code in a pasted link or code: 12 letters and digits (a community
  /// invite's are 10, so the two can't be mistaken for each other).
  static String? codeFrom(String text) {
    final cleaned = text.trim().replaceAll(RegExp(r'[/?#]+$'), '');
    return RegExp(r'(?:^|/)([0-9A-Za-z]{12})$').firstMatch(cleaned)?.group(1);
  }
}

/// What an invite leads to, before joining: "Join Acme Taxis?".
@immutable
class OrgInvitePreview {
  const OrgInvitePreview({required this.org, required this.usable, this.problem});

  factory OrgInvitePreview.fromJson(Map<String, dynamic> json) => OrgInvitePreview(
    org: Org.fromJson(json['org'] as Map<String, dynamic>),
    usable: json['usable'] as bool,
    problem: json['problem'] as String?,
  );

  final Org org;
  final bool usable;

  /// Why it can't be used ("this invite has expired"), when it can't.
  final String? problem;
}
