import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// The browser: hand [bytes] to the browser's own download, as [name].
const canSaveFiles = true;

Future<void> saveFile(Uint8List bytes, String name, String type) async {
  final url = web.URL.createObjectURL(web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: type)));
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  link.click();
  web.URL.revokeObjectURL(url);
}
