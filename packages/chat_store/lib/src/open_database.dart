import 'package:drift_flutter/drift_flutter.dart';

import 'chat_database.dart';

/// Opens (or creates) the device's chat database called [name]: a SQLite
/// file on phones and desktops; in the browser, SQLite compiled to
/// WebAssembly, stored in the browser's own storage. The web needs
/// web/sqlite3.wasm and web/drift_worker.js next to the app, from the
/// releases matching the locked versions (pubspec.lock), currently:
///   https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.5.2/sqlite3.wasm
///   https://github.com/simolus3/drift/releases/download/drift-2.35.3/drift_worker.js
/// Download them again after upgrading sqlite3 or drift.
ChatDatabase openChatDatabase(String name) => ChatDatabase(
      driftDatabase(
        name: name,
        web: DriftWebOptions(sqlite3Wasm: Uri.parse('sqlite3.wasm'), driftWorker: Uri.parse('drift_worker.js')),
      ),
    );
