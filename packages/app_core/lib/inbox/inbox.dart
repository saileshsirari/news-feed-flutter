import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../mini_app/app_links.dart';
import '../push/local_notifications.dart';

/// The notifications inbox: what was shown on this device since the app
/// started, newest first, and how many haven't been looked at. A simple
/// list for now (kept in memory, not on the server).
@immutable
class InboxState {
  const InboxState({this.items = const [], this.unseen = 0});

  final List<ShownNotification> items;
  final int unseen;
}

class InboxNotifier extends Notifier<InboxState> {
  static const maxItems = 50;

  @override
  InboxState build() {
    final sub = shownNotifications.listen(add);
    ref.onDispose(sub.cancel);
    return const InboxState();
  }

  void add(ShownNotification item) =>
      state = InboxState(items: [item, ...state.items].take(maxItems).toList(), unseen: state.unseen + 1);

  /// The inbox was opened: nothing is new any more.
  void markSeen() => state = InboxState(items: state.items);

  void clear() => state = const InboxState();
}

final inboxProvider = NotifierProvider<InboxNotifier, InboxState>(InboxNotifier.new);

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const InboxScreen()));

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  @override
  void initState() {
    super.initState();
    // After this frame: changing a provider while building isn't allowed.
    Future.microtask(() => ref.read(inboxProvider.notifier).markSeen());
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(inboxProvider).items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (items.isNotEmpty)
            TextButton(onPressed: ref.read(inboxProvider.notifier).clear, child: const Text('Clear')),
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text('Nothing new. Notifications you get show up here.'))
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final item = items[i];
                return ListTile(
                  title: Text(item.title),
                  subtitle: Text(item.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Text(DateFormat.jm().format(item.at), style: Theme.of(context).textTheme.bodySmall),
                  onTap: item.link == null ? null : () => openAppLink(context, item.link!),
                );
              },
            ),
    );
  }
}
