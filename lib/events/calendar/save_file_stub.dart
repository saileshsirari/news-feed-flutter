import 'dart:typed_data';

/// Phones and desktops: no browser download; the Google Calendar link is used instead.
const canSaveFiles = false;

Future<void> saveFile(Uint8List bytes, String name, String type) async =>
    throw UnsupportedError('saving files is only for the web build');
