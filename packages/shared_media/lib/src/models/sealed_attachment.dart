import 'dart:convert';
import 'dart:typed_data';

import 'media_attachment.dart';

/// A photo or video uploaded encrypted (see MediaSealer): the server holds
/// only [mediaId]'s encrypted bytes. Everything else here, the key above
/// all, travels inside the end-to-end encrypted message, so only the
/// chat's members know what the file is, or can open it.
class SealedAttachment {
  const SealedAttachment({
    required this.mediaId,
    required this.key,
    required this.kind,
    required this.contentType,
    required this.sizeBytes,
    this.width,
    this.height,
    this.durationMs,
    this.preview,
  });

  factory SealedAttachment.fromJson(Map<String, dynamic> json) => SealedAttachment(
    mediaId: json['id'] as int,
    key: base64Decode(json['key'] as String),
    kind: MediaKind.fromJson(json['kind'] as String),
    contentType: json['contentType'] as String,
    sizeBytes: json['sizeBytes'] as int,
    width: json['width'] as int?,
    height: json['height'] as int?,
    durationMs: json['durationMs'] as int?,
    preview: switch (json['preview']) {
      final String p => base64Decode(p),
      _ => null,
    },
  );

  Map<String, dynamic> toJson() => {
    'id': mediaId,
    'key': base64Encode(key),
    'kind': kind.name,
    'contentType': contentType,
    'sizeBytes': sizeBytes,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (durationMs != null) 'durationMs': durationMs,
    if (preview != null) 'preview': base64Encode(preview!),
  };

  /// Without its [preview] (they're dropped once a message has too many).
  SealedAttachment withoutPreview() => SealedAttachment(
    mediaId: mediaId,
    key: key,
    kind: kind,
    contentType: contentType,
    sizeBytes: sizeBytes,
    width: width,
    height: height,
    durationMs: durationMs,
  );

  /// The server's id for the encrypted file.
  final int mediaId;

  /// What opens it (32 bytes).
  final Uint8List key;
  final MediaKind kind;

  /// What it really is, e.g. image/jpeg or video/mp4.
  final String contentType;

  /// Its size before encrypting.
  final int sizeBytes;
  final int? width;
  final int? height;
  final int? durationMs;

  /// A tiny JPEG of it (a video's first frame), shown before the file
  /// itself has downloaded.
  final Uint8List? preview;

  /// As an attachment the usual widgets can show, once opened: [url] is
  /// where the decrypted file now is on this device.
  MediaAttachment opened(Uri url, {Uri? posterUrl}) => MediaAttachment(
    id: mediaId,
    kind: kind,
    url: url,
    contentType: contentType,
    sizeBytes: sizeBytes,
    width: width,
    height: height,
    durationMs: durationMs,
    thumbnailUrl: posterUrl,
  );

  @override
  bool operator ==(Object other) => other is SealedAttachment && other.mediaId == mediaId;

  @override
  int get hashCode => mediaId.hashCode;
}
