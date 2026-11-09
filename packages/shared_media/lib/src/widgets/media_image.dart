import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/media_attachment.dart';
import '../sealed/local_media.dart';

/// One uploaded image, filling its box. Cached by media id rather than URL:
/// the signed link changes on every feed load, and keying by it would
/// download the same image again each time.
class MediaImage extends StatelessWidget {
  const MediaImage(this.media, {super.key, this.fit = BoxFit.cover});

  final MediaAttachment media;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Decrypted on this device (an end-to-end encrypted chat's photo).
    final local = localImage(media.url);
    if (local != null) {
      return Image(
        image: local,
        fit: fit,
        errorBuilder: (_, _, _) => ColoredBox(
          color: colors.surfaceContainerHighest,
          child: Icon(Icons.broken_image_outlined, color: colors.onSurfaceVariant),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: media.url.toString(),
      cacheKey: 'media:${media.id}',
      fit: fit,
      placeholder: (_, _) => ColoredBox(color: colors.surfaceContainerHighest),
      errorWidget: (_, _, _) => ColoredBox(
        color: colors.surfaceContainerHighest,
        child: Icon(Icons.broken_image_outlined, color: colors.onSurfaceVariant),
      ),
    );
  }
}
