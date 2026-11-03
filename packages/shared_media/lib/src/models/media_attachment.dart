enum MediaKind {
  image,
  video;

  static MediaKind fromJson(String value) => MediaKind.values.byName(value);
}

/// An uploaded, ready file as the server returns it (its `MediaView`),
/// with a short-lived [url] to show it.
class MediaAttachment {
  const MediaAttachment({
    required this.id,
    required this.kind,
    required this.url,
    required this.contentType,
    required this.sizeBytes,
    this.width,
    this.height,
    this.durationMs,
    this.thumbnailUrl,
  });

  factory MediaAttachment.fromJson(Map<String, dynamic> json) => MediaAttachment(
        id: json['id'] as int,
        kind: MediaKind.fromJson(json['kind'] as String),
        url: Uri.parse(json['url'] as String),
        contentType: json['contentType'] as String,
        sizeBytes: json['sizeBytes'] as int,
        width: json['width'] as int?,
        height: json['height'] as int?,
        durationMs: json['durationMs'] as int?,
        thumbnailUrl: switch (json['thumbnailUrl']) { final String url => Uri.parse(url), _ => null },
      );

  final int id;
  final MediaKind kind;
  final Uri url;
  final String contentType;
  final int sizeBytes;
  final int? width;
  final int? height;
  final int? durationMs;

  /// A video's poster image; null for images, or a video uploaded without one.
  final Uri? thumbnailUrl;

  /// Width / height, for reserving space before the image loads; null if unknown.
  double? get aspectRatio => (width != null && height != null && height! > 0) ? width! / height! : null;
}
