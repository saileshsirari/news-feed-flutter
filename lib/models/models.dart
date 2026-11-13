// Mirrors news-feed-android's ApiModels.kt field-for-field — same backend,
// same JSON shape, just Dart's manual fromJson instead of kotlinx.serialization.
// No code generation on purpose: the model set is small and stable, and
// hand-written fromJson is easier to read while still on Flutter fundamentals.

import 'package:shared_media/shared_media.dart';

/// A profile photo: its media id (what it's cached by, since the link
/// changes on every load) and a short-lived link to it.
class ProfilePhoto {
  const ProfilePhoto({required this.id, required this.url});

  static ProfilePhoto? fromJson(Object? json) => switch (json) {
        {'id': final int id, 'url': final String url} => ProfilePhoto(id: id, url: Uri.parse(url)),
        _ => null,
      };

  final int id;
  final Uri url;
}

class User {
  final int id;

  /// The handle (@name): unique, and doesn't change.
  final String username;
  final int createdAt;
  final bool isCelebrity;

  /// The name they chose to show, if any (see [shownName]).
  final String? displayName;
  final String? bio;
  final ProfilePhoto? photo;

  // Counts: only in a full profile (GET /users/:id, /me); zero in lists.
  final int followerCount;
  final int followingCount;
  final int postCount;

  User({
    required this.id,
    required this.username,
    required this.createdAt,
    required this.isCelebrity,
    this.displayName,
    this.bio,
    this.photo,
    this.followerCount = 0,
    this.followingCount = 0,
    this.postCount = 0,
  });

  /// What to call them: their chosen name, or their handle.
  String get shownName => displayName ?? '@$username';

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as int,
        username: json['username'] as String,
        createdAt: json['created_at'] as int,
        isCelebrity: json['is_celebrity'] as bool? ?? false,
        displayName: json['display_name'] as String?,
        bio: json['bio'] as String?,
        photo: ProfilePhoto.fromJson(json['avatar']),
        followerCount: json['followerCount'] as int? ?? 0,
        followingCount: json['followingCount'] as int? ?? 0,
        postCount: json['postCount'] as int? ?? 0,
      );
}

class Post {
  final int id;
  final int authorId;
  final String body;
  final int createdAt;
  final String authorUsername;

  /// The author's profile name and photo, if they set them.
  final String? authorDisplayName;
  final ProfilePhoto? authorPhoto;

  /// Images and videos, in the order the author arranged them.
  final List<MediaAttachment> media;

  final int likeCount;
  final int commentCount;

  /// Whether the signed-in user liked it.
  final bool likedByMe;

  Post({
    required this.id,
    required this.authorId,
    required this.body,
    required this.createdAt,
    required this.authorUsername,
    this.authorDisplayName,
    this.authorPhoto,
    this.media = const [],
    this.likeCount = 0,
    this.commentCount = 0,
    this.likedByMe = false,
  });

  factory Post.fromJson(Map<String, dynamic> json) => Post(
        id: json['id'] as int,
        authorId: json['author_id'] as int,
        body: json['body'] as String,
        createdAt: json['created_at'] as int,
        authorUsername: json['author_username'] as String,
        authorDisplayName: json['author_display_name'] as String?,
        authorPhoto: ProfilePhoto.fromJson(json['author_avatar']),
        media: [
          for (final m in json['media'] as List? ?? const []) MediaAttachment.fromJson(m as Map<String, dynamic>),
        ],
        likeCount: json['like_count'] as int? ?? 0,
        commentCount: json['comment_count'] as int? ?? 0,
        likedByMe: json['liked_by_me'] as bool? ?? false,
      );

  Post copyWith({int? likeCount, int? commentCount, bool? likedByMe}) => Post(
        id: id,
        authorId: authorId,
        body: body,
        createdAt: createdAt,
        authorUsername: authorUsername,
        authorDisplayName: authorDisplayName,
        authorPhoto: authorPhoto,
        media: media,
        likeCount: likeCount ?? this.likeCount,
        commentCount: commentCount ?? this.commentCount,
        likedByMe: likedByMe ?? this.likedByMe,
      );
}

/// A comment on a post.
/// A comment on a post, in a thread: replies point at their [parentId], and
/// [path] orders the whole thread for reading (each comment, then its
/// replies). See the server's schema.sql for how paths are made.
class PostComment {
  final int id;
  final int postId;
  final int? parentId;
  final int authorId;
  final String authorUsername;
  final String body;
  final int createdAt;
  final String path;

  /// 0 for a comment on the post, 1 for a reply, and so on.
  final int depth;

  /// Direct replies.
  final int replyCount;

  /// Deleted, but kept as "[deleted]" because it has replies.
  final bool deleted;

  PostComment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorUsername,
    required this.body,
    required this.createdAt,
    this.parentId,
    String? path,
    this.depth = 0,
    this.replyCount = 0,
    this.deleted = false,
  }) : path = path ?? '';

  factory PostComment.fromJson(Map<String, dynamic> json) => PostComment(
        id: json['id'] as int,
        postId: json['post_id'] as int,
        parentId: json['parent_id'] as int?,
        authorId: json['author_id'] as int,
        authorUsername: json['author_username'] as String,
        body: json['body'] as String,
        createdAt: json['created_at'] as int,
        path: json['path'] as String?,
        depth: json['depth'] as int? ?? 0,
        replyCount: json['reply_count'] as int? ?? 0,
        deleted: json['deleted'] as bool? ?? false,
      );

  PostComment copyWith({int? replyCount, bool? deleted}) => PostComment(
        id: id,
        postId: postId,
        parentId: parentId,
        authorId: deleted == true ? 0 : authorId,
        authorUsername: deleted == true ? '' : authorUsername,
        body: deleted == true ? '' : body,
        createdAt: createdAt,
        path: path,
        depth: depth,
        replyCount: replyCount ?? this.replyCount,
        deleted: deleted ?? this.deleted,
      );
}

class CreatePostResponse {
  final Post post;
  final double fanoutMs;

  CreatePostResponse({required this.post, required this.fanoutMs});

  factory CreatePostResponse.fromJson(Map<String, dynamic> json) => CreatePostResponse(
        post: Post.fromJson(json),
        fanoutMs: (json['fanoutMs'] as num).toDouble(),
      );
}

class FeedPage {
  final List<Post> posts;
  final String? nextCursor;

  FeedPage({required this.posts, this.nextCursor});

  factory FeedPage.fromJson(Map<String, dynamic> json) => FeedPage(
        posts: (json['posts'] as List).map((p) => Post.fromJson(p as Map<String, dynamic>)).toList(),
        nextCursor: json['nextCursor'] as String?,
      );
}

class NewerFeedPage {
  final List<Post> posts;
  final String? newestCursor;

  NewerFeedPage({required this.posts, this.newestCursor});

  factory NewerFeedPage.fromJson(Map<String, dynamic> json) => NewerFeedPage(
        posts: (json['posts'] as List).map((p) => Post.fromJson(p as Map<String, dynamic>)).toList(),
        newestCursor: json['newestCursor'] as String?,
      );
}

class Conversation {
  final int id;
  final bool isGroup;
  final String? name;

  Conversation({required this.id, required this.isGroup, this.name});

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as int,
        isGroup: json['is_group'] as bool,
        name: json['name'] as String?,
      );
}

/// One row of the contact list's "Chats" tab — GET /conversations.
class ConversationSummary {
  final int id;
  final bool isGroup;
  final String? name;
  /// The other participant's username — only set for a 1:1 conversation;
  /// null for groups, which use [name] as their title instead.
  final String? otherUsername;

  /// Same, the other participant's id, for their presence; null for groups.
  final int? otherUserId;
  final String? lastMessageBody;
  final int? lastMessageCreatedAt;

  /// The newest message's seq: a device behind it has news to sync.
  final int lastSeq;
  final int unreadCount;

  /// End-to-end encrypted (for good), and its MLS group.
  final bool isE2e;
  final String? mlsGroupId;

  ConversationSummary({
    required this.id,
    required this.isGroup,
    this.name,
    this.otherUsername,
    this.otherUserId,
    this.lastMessageBody,
    this.lastMessageCreatedAt,
    this.lastSeq = 0,
    required this.unreadCount,
    this.isE2e = false,
    this.mlsGroupId,
  });

  /// What to show as this row's title — a group's name, or "@" + the other
  /// person's username for a 1:1. Centralized here so every screen that
  /// lists conversations resolves the title identically.
  String displayTitle() => isGroup ? (name ?? 'Group chat') : '@${otherUsername ?? 'unknown'}';

  factory ConversationSummary.fromJson(Map<String, dynamic> json) => ConversationSummary(
        id: json['id'] as int,
        isGroup: json['is_group'] as bool,
        name: json['name'] as String?,
        otherUsername: json['other_username'] as String?,
        otherUserId: json['other_user_id'] as int?,
        lastMessageBody: json['last_message_body'] as String?,
        lastMessageCreatedAt: json['last_message_created_at'] as int?,
        lastSeq: json['last_seq'] as int? ?? 0,
        unreadCount: json['unread_count'] as int,
        isE2e: json['encryption'] == 'e2e',
        mlsGroupId: json['mls_group_id'] as String?,
      );
}

class ChatMessage {
  final int id;
  final int conversationId;

  /// Its place in the conversation: 1, 2, 3, ... (0 from an older server).
  final int seq;
  final int senderId;
  final String body;
  final int createdAt;
  final String senderUsername;

  /// Photos and videos, in the order the sender arranged them.
  final List<MediaAttachment> media;

  /// An encrypted message's photos and videos (what each is, and its key),
  /// from the decrypted message. Its [media] stays empty: the server's
  /// copies are just encrypted bytes.
  final List<SealedAttachment> sealedMedia;

  /// The message exactly as the server sent it: what the device stores.
  final Map<String, dynamic> json;

  /// Emoji reactions, grouped by emoji, oldest group first.
  final List<MessageReaction> reactions;

  /// server, e2e (end-to-end encrypted), commit (an encrypted group change:
  /// nothing to show) or notice (about the chat itself).
  final String mode;

  /// Which of the sender's devices sent it.
  final int? senderDeviceId;

  bool get isE2e => mode == 'e2e';
  bool get isNotice => mode == 'notice';
  bool get isGroupChange => mode == 'commit';

  /// An encrypted message this device has the text of. (Until then, [body]
  /// is a placeholder.)
  bool get isDecrypted => json['decrypted'] == true;

  ChatMessage({
    required this.id,
    required this.conversationId,
    this.seq = 0,
    required this.senderId,
    required this.body,
    required this.createdAt,
    required this.senderUsername,
    this.media = const [],
    this.sealedMedia = const [],
    this.json = const {},
    this.reactions = const [],
    this.mode = 'server',
    this.senderDeviceId,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as int,
        conversationId: json['conversation_id'] as int,
        seq: json['seq'] as int? ?? 0,
        json: json,
        mode: json['mode'] as String? ?? 'server',
        senderDeviceId: json['sender_device_id'] as int?,
        reactions: [
          for (final r in json['reactions'] as List? ?? const []) MessageReaction.fromJson(r as Map<String, dynamic>),
        ],
        senderId: json['sender_id'] as int,
        body: json['body'] as String,
        createdAt: json['created_at'] as int,
        senderUsername: json['sender_username'] as String,
        media: [
          // An encrypted message's files are opened from sealedMedia instead.
          if (json['mode'] != 'e2e')
            for (final m in json['media'] as List? ?? const []) MediaAttachment.fromJson(m as Map<String, dynamic>),
        ],
        sealedMedia: [
          for (final m in json['sealed_media'] as List? ?? const []) SealedAttachment.fromJson(m as Map<String, dynamic>),
        ],
      );
}

/// Everyone who reacted to a message with one emoji.
class MessageReaction {
  final String emoji;
  final List<int> userIds;

  MessageReaction({required this.emoji, required this.userIds});

  factory MessageReaction.fromJson(Map<String, dynamic> json) => MessageReaction(
        emoji: json['emoji'] as String,
        userIds: [for (final id in json['user_ids'] as List) id as int],
      );
}

/// One participant's read pointer — GET /conversations/:id/reads returns one
/// of these per participant (0 for anyone who's never opened it).
class ReadState {
  final int userId;
  final String username;
  final int lastReadMessageId;

  /// How far this member's devices have received the chat (✓✓ grey).
  final int lastDeliveredMessageId;

  ReadState({
    required this.userId,
    this.username = '',
    required this.lastReadMessageId,
    int? lastDeliveredMessageId,
  }) : lastDeliveredMessageId = lastDeliveredMessageId ?? lastReadMessageId;

  factory ReadState.fromJson(Map<String, dynamic> json) => ReadState(
        userId: json['user_id'] as int,
        username: json['username'] as String? ?? '',
        lastReadMessageId: json['last_read_message_id'] as int,
        lastDeliveredMessageId: json['last_delivered_message_id'] as int?,
      );
}

/// GET /conversations/:id/call-token's response — everything the Flutter
/// client needs to join this conversation's LiveKit room: a scoped JWT, the
/// LiveKit server's own url (a separate service from AppConfig.apiBaseUrl, so
/// the backend hands it back rather than the client guessing it), and the
/// room name (== "conversation-<id>", but the client shouldn't hardcode that
/// convention — see chatService.createCallToken).
class CallToken {
  final String token;
  final String url;
  final String roomName;

  CallToken({required this.token, required this.url, required this.roomName});

  factory CallToken.fromJson(Map<String, dynamic> json) => CallToken(
        token: json['token'] as String,
        url: json['url'] as String,
        roomName: json['roomName'] as String,
      );
}

class MessagePage {
  final List<ChatMessage> messages;
  final String? nextCursor;

  MessagePage({required this.messages, this.nextCursor});

  factory MessagePage.fromJson(Map<String, dynamic> json) => MessagePage(
        messages: (json['messages'] as List).map((m) => ChatMessage.fromJson(m as Map<String, dynamic>)).toList(),
        nextCursor: json['nextCursor'] as String?,
      );
}

/// Whether someone is online now, or when they last were.
class Presence {
  const Presence({required this.userId, required this.online, this.lastSeenAt});

  factory Presence.fromJson(Map<String, dynamic> json) => Presence(
        userId: json['userId'] as int,
        online: json['online'] as bool,
        lastSeenAt: json['lastSeenAt'] as int?,
      );

  final int userId;
  final bool online;

  /// Milliseconds since epoch; null if online, or never seen.
  final int? lastSeenAt;
}
