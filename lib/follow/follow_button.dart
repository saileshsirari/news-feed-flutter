import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'following_notifier.dart';

/// "Follow" / "Following" for one user. Disabled until the current follows
/// are known, and while a change for this user is being sent.
class FollowButton extends ConsumerWidget {
  const FollowButton({super.key, required this.userId, required this.username});

  final int userId;

  /// For the error message.
  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = ref.watch(followingProvider);
    final isFollowing = following.follows(userId);
    final onPressed = !following.isLoaded || following.isPending(userId)
        ? null
        : () async {
            final ok = await ref.read(followingProvider.notifier).toggle(userId);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Couldn\'t ${isFollowing ? 'unfollow' : 'follow'} @$username. Try again.')),
              );
            }
          };

    return isFollowing
        ? OutlinedButton(onPressed: onPressed, child: const Text('Following'))
        : FilledButton.tonal(onPressed: onPressed, child: const Text('Follow'));
  }
}
