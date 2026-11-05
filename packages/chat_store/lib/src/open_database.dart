import 'package:drift_flutter/drift_flutter.dart';

import 'chat_database.dart';

/// Opens (or creates) the device's chat database called [name]: a SQLite
/// file on phones and desktops; in the browser, SQLite compiled to
/// WebAssembly, stored in the browser's own storage. The web needs
/// web/sqlite3.wasm and web/drift_worker.js next to the app.
ChatDatabase openChatDatabase(String name) => ChatDatabase(
      driftDatabase(
        name: name,
        web: DriftWebOptions(sqlite3Wasm: Uri.parse('sqlite3.wasm'), driftWorker: Uri.parse('drift_worker.js')),
      ),
    );
