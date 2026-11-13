import 'package:flutter/material.dart';
import 'package:shared_media/shared_media.dart';

import '../models/models.dart';

/// Someone's round profile photo, or the first letter of their name on a
/// coloured circle when they have none (or it can't load).
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.photo, this.radius = 20});

  UserAvatar.of(User user, {Key? key, double radius = 20})
    : this(key: key, name: user.displayName ?? user.username, photo: user.photo, radius: radius);

  /// For the letter: their display name or username.
  final String name;
  final ProfilePhoto? photo;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final letter = Text(
      name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
      style: TextStyle(fontSize: radius * 0.8, color: colors.onPrimaryContainer),
    );
    final photo = this.photo;
    return SizedBox.square(
      dimension: radius * 2,
      child: ClipOval(
        child: ColoredBox(
          color: colors.primaryContainer,
          child: photo == null
              ? Center(child: letter)
              // MediaImage caches by media id, so the photo isn't fetched
              // again each time its link changes.
              : MediaImage(
                  MediaAttachment(
                    id: photo.id,
                    kind: MediaKind.image,
                    url: photo.url,
                    contentType: 'image/jpeg',
                    sizeBytes: 0,
                  ),
                ),
        ),
      ),
    );
  }
}
