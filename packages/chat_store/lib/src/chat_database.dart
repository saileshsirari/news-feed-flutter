import 'package:drift/drift.dart';

part 'chat_database.g.dart';

/// One message as kept on the device.
///
/// The message itself is stored as the server sent it ([json]): this package
/// doesn't need to understand messages, only to order, sync and search them,
/// so it pulls out just the columns it queries. (End-to-end encrypted
/// messages will be stored the same way, after the device decrypts them.)
@DataClassName('StoredMessage')
class ChatMessages extends Table {
  IntColumn get conversationId => integer()();

  /// Its place in the conversation: 1, 2, 3, ... (the server's seq).
  IntColumn get seq => integer()();

  /// The server's id for it.
  IntColumn get messageId => integer()();

  /// The text, for search.
  TextColumn get body => text()();
  IntColumn get createdAt => integer()();

  /// The whole message as the server sent it.
  TextColumn get json => text()();

  /// When this copy came from the server (photo links in [json] expire).
  IntColumn get fetchedAt => integer()();

  @override
  Set<Column> get primaryKey => {conversationId, seq};
}

/// Which runs of a conversation this device has, e.g. 1-4200 and 9940-9970:
/// a device that was offline a long time jumps to the newest messages and
/// leaves a gap, filled only if you scroll back into it. Ranges never
/// overlap or touch; touching ones are merged.
class SyncedRanges extends Table {
  IntColumn get conversationId => integer()();
  IntColumn get lowSeq => integer()();
  IntColumn get highSeq => integer()();

  @override
  Set<Column> get primaryKey => {conversationId, lowSeq};
}

/// Small named values that belong to this device and user, such as the
/// end-to-end encryption state (already sealed before it gets here).
class DeviceBlobs extends Table {
  TextColumn get name => text()();
  BlobColumn get value => blob()();

  @override
  Set<Column> get primaryKey => {name};
}

@DriftDatabase(tables: [ChatMessages, SyncedRanges, DeviceBlobs])
class ChatDatabase extends _$ChatDatabase {
  ChatDatabase(super.executor);

  /// 1: messages, synced ranges, search. 2: DeviceBlobs.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Full-text search over message text (SQLite's FTS5), kept in step
          // with chat_messages by triggers, so every write path stays
          // searchable without remembering to update it.
          for (final statement in _searchIndex) {
            await customStatement(statement);
          }
        },
        // Existing installs keep their messages and gain the new table.
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(deviceBlobs);
        },
      );

  static const _searchIndex = [
    // External content: the index points at chat_messages rows instead of
    // keeping a second copy of every text. unicode61 with diacritics removed
    // so "cafe" finds "café".
    "CREATE VIRTUAL TABLE chat_message_search USING fts5(body, content='chat_messages', "
        "content_rowid='rowid', tokenize='unicode61 remove_diacritics 2')",
    'CREATE TRIGGER chat_messages_ai AFTER INSERT ON chat_messages BEGIN '
        'INSERT INTO chat_message_search(rowid, body) VALUES (new.rowid, new.body); END',
    'CREATE TRIGGER chat_messages_ad AFTER DELETE ON chat_messages BEGIN '
        "INSERT INTO chat_message_search(chat_message_search, rowid, body) VALUES ('delete', old.rowid, old.body); END",
    'CREATE TRIGGER chat_messages_au AFTER UPDATE ON chat_messages BEGIN '
        "INSERT INTO chat_message_search(chat_message_search, rowid, body) VALUES ('delete', old.rowid, old.body); "
        'INSERT INTO chat_message_search(rowid, body) VALUES (new.rowid, new.body); END',
  ];
}
