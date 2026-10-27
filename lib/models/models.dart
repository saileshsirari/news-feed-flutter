// Mirrors news-feed-android's ApiModels.kt field-for-field — same backend,
// same JSON shape, just Dart's manual fromJson instead of kotlinx.serialization.
// No code generation on purpose: the model set is small and stable, and
// hand-written fromJson is easier to read while still on Flutter fundamentals.

class User {
  final int id;
  final String username;
  final int createdAt;
  final bool isCelebrity;
  final int followerCount;

  User({
    required this.id,
    required this.username,
    required this.createdAt,
    required this.isCelebrity,
    this.followerCount = 0,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as int,
        username: json['username'] as String,
        createdAt: json['created_at'] as int,
        isCelebrity: json['is_celebrity'] as bool? ?? false,
        followerCount: json['followerCount'] as int? ?? 0,
      );
}

class Post {
  final int id;
  final int authorId;
  final String body;
  final int createdAt;
  final String authorUsername;

  Post({
    required this.id,
    required this.authorId,
    required this.body,
    required this.createdAt,
    required this.authorUsername,
  });

  factory Post.fromJson(Map<String, dynamic> json) => Post(
        id: json['id'] as int,
        authorId: json['author_id'] as int,
        body: json['body'] as String,
        createdAt: json['created_at'] as int,
        authorUsername: json['author_username'] as String,
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
  final String? lastMessageBody;
  final int? lastMessageCreatedAt;
  final int unreadCount;

  ConversationSummary({
    required this.id,
    required this.isGroup,
    this.name,
    this.otherUsername,
    this.lastMessageBody,
    this.lastMessageCreatedAt,
    required this.unreadCount,
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
        lastMessageBody: json['last_message_body'] as String?,
        lastMessageCreatedAt: json['last_message_created_at'] as int?,
        unreadCount: json['unread_count'] as int,
      );
}

class ChatMessage {
  final int id;
  final int conversationId;
  final int senderId;
  final String body;
  final int createdAt;
  final String senderUsername;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    required this.senderUsername,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as int,
        conversationId: json['conversation_id'] as int,
        senderId: json['sender_id'] as int,
        body: json['body'] as String,
        createdAt: json['created_at'] as int,
        senderUsername: json['sender_username'] as String,
      );
}

/// One participant's read pointer — GET /conversations/:id/reads returns one
/// of these per participant (0 for anyone who's never opened it).
class ReadState {
  final int userId;
  final int lastReadMessageId;

  ReadState({required this.userId, required this.lastReadMessageId});

  factory ReadState.fromJson(Map<String, dynamic> json) => ReadState(
        userId: json['user_id'] as int,
        lastReadMessageId: json['last_read_message_id'] as int,
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
