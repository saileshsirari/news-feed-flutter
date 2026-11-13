import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'event_tile.dart';
import 'events_providers.dart';

/// A community's events as a list that loads more as asked, or a short
/// message when there are none.
class EventList extends ConsumerWidget {
  const EventList({super.key, required this.communityId, required this.past, this.shrinkWrap = false});

  final int communityId;
  final bool past;

  /// Inside another scrolling list (the community page).
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (communityId: communityId, past: past);
    final events = ref.watch(communityEventsProvider(key));
    return switch (events) {
      AsyncData(:final value) when value.items.isEmpty => Padding(
          padding: const EdgeInsets.all(16),
          child: Text(past ? 'No past events.' : 'Nothing planned yet.'),
        ),
      AsyncData(:final value) => ListView(
          shrinkWrap: shrinkWrap,
          physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
          children: [
            for (final e in value.items) EventTile(e),
            if (value.hasMore)
              Center(
                child: TextButton(
                  onPressed: () => ref.read(communityEventsProvider(key).notifier).loadMore(),
                  child: const Text('More events'),
                ),
              ),
          ],
        ),
      AsyncError() => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(communityEventsProvider(key)),
            child: const Text('Couldn\'t load events. Try again'),
          ),
        ),
      _ => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
    };
  }
}
