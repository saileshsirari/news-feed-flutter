/// Where this device keeps files it has decrypted, and how to show them.
library;

export 'local_media_io.dart' if (dart.library.js_interop) 'local_media_web.dart';
