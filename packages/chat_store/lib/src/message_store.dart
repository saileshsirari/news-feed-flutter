import 'package:drift/drift.dart';

import 'chat_database.dart';

/// A message as it comes from the server, with the few fields the store
/// needs pulled out; [json] is the whole message, kept as is.
class RemoteMessage {
  const RemoteMessage({
    required this.conversationId,
    required this.seq,
    required this.messageId,
    required this.body,
    required this.createdAt,
    required this.json,
    this.overwrite = true,
  });

  final int conversationId;

  /// False: only store it if this device doesn't have it yet. For a copy
  /// that must never replace what's there, like an end-to-end encrypted
  /// message's ciphertext over the text this device already decrypted.
  final bool overwrite;
  final int seq;
  final int messageId;
  final String body;
  final int createdAt;
  final String json;
}

/// One run of a conversation the device has, inclusive.
typedef SeqRange = ({int low, int high});

/// A search result: the message, and its text with the matches marked by
/// [MessageStore.matchStart] and [MessageStore.matchEnd].
class SearchHit {
  const SearchHit(this.message, this.snippet);
  final StoredMessage message;
  final String snippet;
}

/// The device's copy of chat history: what's stored, which runs of each
/// conversation it covers, and search. No network here (see ChatSync).
class MessageStore {
  MessageStore(this.db, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final ChatDatabase db;
  final DateTime Function() _now;

  /// Marks around matched words in [SearchHit.snippet]; private-use
  /// characters, so they can't clash with anything typed in a message.
  static const matchStart = '';
  static const matchEnd = '';

  /// Saves [messages] (new ones, or fresh copies of ones already here).
  Future<void> upsertAll(List<RemoteMessage> messages) async {
    if (messages.isEmpty) return;
    final now = _now().millisecondsSinceEpoch;
    ChatMessagesCompanion row(RemoteMessage m) => ChatMessagesCompanion.insert(
          conversationId: m.conversationId,
          seq: m.seq,
          messageId: m.messageId,
          body: m.body,
          createdAt: m.createdAt,
          json: m.json,
          fetchedAt: now,
        );
    await db.batch((batch) {
      batch.insertAllOnConflictUpdate(db.chatMessages, [for (final m in messages) if (m.overwrite) row(m)]);
      batch.insertAll(db.chatMessages, [for (final m in messages) if (!m.overwrite) row(m)], mode: InsertMode.insertOrIgnore);
    });
  }

  /// One stored message by its server id, if this device has it.
  Future<StoredMessage?> byMessageId(int conversationId, int messageId) => (db.select(db.chatMessages)
        ..where((m) => m.conversationId.equals(conversationId) & m.messageId.equals(messageId)))
      .getSingleOrNull();

  /// Replaces a stored message's JSON (e.g. its reactions changed), keeping
  /// its place; does nothing if this device doesn't have it.
  Future<void> updateJson(int conversationId, int messageId, String json) async {
    await (db.update(db.chatMessages)
          ..where((m) => m.conversationId.equals(conversationId) & m.messageId.equals(messageId)))
        .write(ChatMessagesCompanion(json: Value(json)));
  }

  /// This conversation's runs, newest first.
  Future<List<SeqRange>> ranges(int conversationId) async {
    final rows = await (db.select(db.syncedRanges)
          ..where((r) => r.conversationId.equals(conversationId))
          ..orderBy([(r) => OrderingTerm.desc(r.highSeq)]))
        .get();
    return [for (final r in rows) (low: r.lowSeq, high: r.highSeq)];
  }

  /// The run holding the newest messages the device has, if any.
  Future<SeqRange?> newestRange(int conversationId) async {
    final all = await ranges(conversationId);
    return all.isEmpty ? null : all.first;
  }

  Stream<SeqRange?> watchNewestRange(int conversationId) => (db.select(db.syncedRanges)
        ..where((r) => r.conversationId.equals(conversationId))
        ..orderBy([(r) => OrderingTerm.desc(r.highSeq)])
        ..limit(1))
      .watchSingleOrNull()
      .map((r) => r == null ? null : (low: r.lowSeq, high: r.highSeq));

  /// Records that the device now has [low]..[high], merging it with any run
  /// it overlaps or touches, so ranges stay few and gap-accurate.
  Future<void> addRange(int conversationId, int low, int high) async {
    await db.transaction(() async {
      final touching = await (db.select(db.syncedRanges)
            ..where((r) =>
                r.conversationId.equals(conversationId) &
                r.lowSeq.isSmallerOrEqualValue(high + 1) &
                r.highSeq.isBiggerOrEqualValue(low - 1)))
          .get();
      var newLow = low;
      var newHigh = high;
      for (final r in touching) {
        if (r.lowSeq < newLow) newLow = r.lowSeq;
        if (r.highSeq > newHigh) newHigh = r.highSeq;
      }
      await (db.delete(db.syncedRanges)
            ..where((r) =>
                r.conversationId.equals(conversationId) &
                r.lowSeq.isIn([for (final r in touching) r.lowSeq])))
          .go();
      await db.into(db.syncedRanges).insert(
            SyncedRangesCompanion.insert(conversationId: conversationId, lowSeq: newLow, highSeq: newHigh),
          );
    });
  }

  /// The conversation's messages from [fromSeq] up, oldest first, updating
  /// whenever they change.
  Stream<List<StoredMessage>> watchFrom(int conversationId, int fromSeq) => (db.select(db.chatMessages)
        ..where((m) => m.conversationId.equals(conversationId) & m.seq.isBiggerOrEqualValue(fromSeq))
        ..orderBy([(m) => OrderingTerm.asc(m.seq)]))
      .watch();

  /// Seqs in [low]..[high] whose copy is older than [maxAge] (their photo
  /// links may have expired).
  Future<List<int>> staleSeqs(int conversationId, int low, int high, Duration maxAge) async {
    final cutoff = _now().subtract(maxAge).millisecondsSinceEpoch;
    final rows = await (db.selectOnly(db.chatMessages)
          ..addColumns([db.chatMessages.seq])
          ..where(db.chatMessages.conversationId.equals(conversationId) &
              db.chatMessages.seq.isBetweenValues(low, high) &
              db.chatMessages.fetchedAt.isSmallerThanValue(cutoff)))
        .get();
    return [for (final r in rows) r.read(db.chatMessages.seq)!];
  }

  /// Messages whose text has every word of [query] (each also as a prefix:
  /// "photo" finds "photos"), newest first; in one conversation if given.
  Future<List<SearchHit>> search(String query, {int? conversationId, int limit = 50}) async {
    final match = ftsQuery(query);
    if (match == null) return [];
    final rows = await db.customSelect(
      'SELECT m.*, snippet(chat_message_search, 0, ?, ?, \'…\', 12) AS snippet '
      'FROM chat_message_search JOIN chat_messages m ON m.rowid = chat_message_search.rowid '
      'WHERE chat_message_search MATCH ? ${conversationId == null ? '' : 'AND m.conversation_id = ?'} '
      'ORDER BY m.created_at DESC LIMIT ?',
      variables: [
        Variable.withString(matchStart),
        Variable.withString(matchEnd),
        Variable.withString(match),
        if (conversationId != null) Variable.withInt(conversationId),
        Variable.withInt(limit),
      ],
      readsFrom: {db.chatMessages},
    ).get();
    return [
      for (final row in rows) SearchHit(db.chatMessages.map(row.data), row.read<String>('snippet')),
    ];
  }

  /// What someone typed, as a safe FTS5 query: each word quoted (so
  /// punctuation and words like OR or NEAR are just text) and matched as a
  /// prefix; all words must appear. Null if there's nothing to look for.
  static String? ftsQuery(String input) {
    final words = input
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll('"', ''))
        .where((w) => w.trim().isNotEmpty)
        .toList();
    if (words.isEmpty) return null;
    return words.map((w) => '"$w"*').join(' ');
  }

  /// A named value kept for this device (see DeviceBlobs), or null.
  Future<Uint8List?> blob(String name) async =>
      (await (db.select(db.deviceBlobs)..where((b) => b.name.equals(name))).getSingleOrNull())?.value;

  Future<void> putBlob(String name, Uint8List value) =>
      db.into(db.deviceBlobs).insertOnConflictUpdate(DeviceBlobsCompanion.insert(name: name, value: value));

  /// Forgets everything (logging out), the device's saved values included.
  Future<void> clear() async {
    await db.transaction(() async {
      await db.delete(db.chatMessages).go();
      await db.delete(db.syncedRanges).go();
      await db.delete(db.deviceBlobs).go();
    });
  }
}
