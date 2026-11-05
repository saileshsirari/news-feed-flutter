/// For tests of apps using chat_store: a database in memory, so nothing is
/// written to disk and every test starts empty.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';

import 'src/chat_database.dart';

ChatDatabase inMemoryChatDatabase() {
  // Tests open one per container, which drift would otherwise warn about.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return ChatDatabase(NativeDatabase.memory());
}
