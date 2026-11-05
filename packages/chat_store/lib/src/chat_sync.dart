import 'message_store.dart';

/// A page of messages from the server, and whether there are more that way.
class SyncPage {
  const SyncPage(this.messages, {required this.hasMore});
  final List<RemoteMessage> messages;
  final bool hasMore;
}

/// How the sync engine reaches the server; the app provides it.
abstract interface class MessageSource {
  /// After [afterSeq], oldest first.
  Future<SyncPage> after(int conversationId, int afterSeq, int limit);

  /// Before [beforeSeq], newest first.
  Future<SyncPage> before(int conversationId, int beforeSeq, int limit);
}

/// Larger than any seq; "before this" means "the newest page".
const _end = 9007199254740991; // 2^53 - 1, safe on the web too

/// Keeps the device's copy of each conversation up to date from the server,
/// using each message's seq (its place in the conversation):
///
///   - opening a chat fetches the newest page: one request that shows how
///     far behind this device is, and refreshes recent photo links;
///   - a little behind: fetch forward page by page until caught up;
///   - far behind (more than [catchUpLimit] messages): keep just the newest
///     page and leave a gap, filled only if you scroll back into it, instead
///     of downloading thousands of messages nobody may read;
///   - scrolling up: [loadOlder] fetches the page before what's on screen.
///
/// Work on one conversation runs one step at a time, so a socket event and
/// a screen opening at once don't fetch the same pages twice.
class ChatSync {
  ChatSync(this.store, this.source, {this.pageSize = 50, this.catchUpLimit = 300});

  final MessageStore store;
  final MessageSource source;
  final int pageSize;
  final int catchUpLimit;

  final _queues = <int, Future<void>>{};

  /// Runs [task] after any earlier work on [conversationId].
  Future<T> _serially<T>(int conversationId, Future<T> Function() task) {
    final previous = _queues[conversationId] ?? Future<void>.value();
    final result = previous.then((_) => task(), onError: (_) => task());
    _queues[conversationId] = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Brings the newest messages in (opening a chat, or after reconnecting).
  Future<void> syncLatest(int conversationId) => _serially(conversationId, () => _syncLatest(conversationId));

  /// A message with [seq] was just sent in [conversationId] (a socket
  /// event): fetch only what's missing up to it.
  Future<void> onNewMessage(int conversationId, int seq) => _serially(conversationId, () async {
        final newest = await store.newestRange(conversationId);
        if (newest != null && seq <= newest.high) return; // already have it
        if (newest != null && seq - newest.high <= catchUpLimit) {
          await _fetchForward(conversationId, newest.high, seq);
        } else {
          await _syncLatest(conversationId);
        }
      });

  /// Fetches the page just before the oldest message in the newest run
  /// (what's on screen), joining up with an older run if it reaches one.
  /// False when there's nothing older.
  Future<bool> loadOlder(int conversationId) => _serially(conversationId, () async {
        final newest = await store.newestRange(conversationId);
        if (newest == null) {
          await _syncLatest(conversationId);
          return (await store.newestRange(conversationId)) != null;
        }
        if (newest.low <= 1) return false;
        final page = await source.before(conversationId, newest.low, pageSize);
        if (page.messages.isEmpty) {
          // Nothing older exists after all (e.g. deleted): the run starts here.
          await store.addRange(conversationId, 1, newest.high);
          return false;
        }
        await store.upsertAll(page.messages);
        final oldest = page.messages.last.seq;
        await store.addRange(conversationId, page.hasMore ? oldest : 1, newest.high);
        return true;
      });

  /// Re-fetches any messages in [low]..[high] whose copy is older than
  /// [maxAge], for fresh photo links. Messages already seen keep their
  /// photos in the image cache, so this is only for ones not yet shown.
  Future<void> refreshStale(int conversationId, int low, int high, {Duration maxAge = const Duration(minutes: 50)}) =>
      _serially(conversationId, () async {
        final stale = await store.staleSeqs(conversationId, low, high, maxAge);
        if (stale.isEmpty) return;
        stale.sort();
        var from = stale.first;
        while (from <= stale.last) {
          final page = await source.after(conversationId, from - 1, pageSize);
          await store.upsertAll(page.messages);
          if (page.messages.isEmpty || !page.hasMore) break;
          from = page.messages.last.seq + 1;
        }
      });

  Future<void> _syncLatest(int conversationId) async {
    final page = await source.before(conversationId, _end, pageSize);
    if (page.messages.isEmpty) return; // an empty conversation
    await store.upsertAll(page.messages);
    final newestSeq = page.messages.first.seq;
    final pageLow = page.hasMore ? page.messages.last.seq : 1;

    final newest = await store.newestRange(conversationId);
    if (newest != null && pageLow > newest.high + 1 && pageLow - newest.high <= catchUpLimit) {
      // A little behind: fill the few pages between, so it's one run.
      await _fetchForward(conversationId, newest.high, pageLow - 1);
    }
    // Merges with the run below if it now touches; otherwise a gap stays.
    await store.addRange(conversationId, pageLow, newestSeq);
  }

  /// Fetches after [fromSeq] until at least [toSeq] (or the end), extending
  /// the run that ends at [fromSeq].
  Future<void> _fetchForward(int conversationId, int fromSeq, int toSeq) async {
    var after = fromSeq;
    while (after < toSeq) {
      // No more than needed: the rest may already be here.
      final limit = toSeq - after < pageSize ? toSeq - after : pageSize;
      final page = await source.after(conversationId, after, limit);
      if (page.messages.isEmpty) break;
      await store.upsertAll(page.messages);
      final high = page.messages.last.seq;
      await store.addRange(conversationId, after + 1, high);
      after = high;
      if (!page.hasMore) break;
    }
  }
}
