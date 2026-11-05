/// Chat history kept on the device: SQLite (through drift) on every
/// platform, synced from the server by each message's seq, with local
/// full-text search. Like shared_media and oidc_auth it knows nothing about
/// the app; the app supplies a [MessageSource] (its API) and decides how to
/// show a stored message (its JSON).
library;

export 'src/chat_database.dart' show ChatDatabase, StoredMessage;
export 'src/chat_sync.dart';
export 'src/message_store.dart';
export 'src/open_database.dart';
