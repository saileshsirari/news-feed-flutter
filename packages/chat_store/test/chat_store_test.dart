import 'dart:convert';

import 'package:chat_store/chat_store.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// A pretend server: conversation 1 has [count] messages, seq 1..count.
class FakeServer implements MessageSource {
  FakeServer(this.count);

  int count;
  final calls = <String>[];
  final limits = <int>[];
  final bodies = <int, String>{};

  RemoteMessage message(int seq) {
    final body = bodies[seq] ?? 'message $seq';
    return RemoteMessage(
      conversationId: 1,
      seq: seq,
      messageId: 1000 + seq,
      body: body,
      createdAt: seq * 1000,
      json: jsonEncode({'seq': seq, 'body': body}),
    );
  }

  @override
  Future<SyncPage> after(int conversationId, int afterSeq, int limit) async {
    calls.add('after $afterSeq');
    limits.add(limit);
    final seqs = [for (var s = afterSeq + 1; s <= count && s <= afterSeq + limit; s++) s];
    return SyncPage([for (final s in seqs) message(s)], hasMore: (seqs.lastOrNull ?? afterSeq) < count);
  }

  @override
  Future<SyncPage> before(int conversationId, int beforeSeq, int limit) async {
    calls.add('before ${beforeSeq > count ? 'end' : beforeSeq}');
    final top = (beforeSeq > count ? count + 1 : beforeSeq) - 1;
    final seqs = [for (var s = top; s >= 1 && s > top - limit; s--) s];
    return SyncPage([for (final s in seqs) message(s)], hasMore: (seqs.lastOrNull ?? 1) > 1);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late ChatDatabase db;
  late MessageStore store;
  late DateTime now;

  setUp(() {
    db = ChatDatabase(NativeDatabase.memory());
    now = DateTime(2026, 11, 5, 12);
    store = MessageStore(db, clock: () => now);
  });

  tearDown(() => db.close());

  Future<List<int>> storedSeqs() async => [for (final m in await store.watchFrom(1, 0).first) m.seq];

  group('syncing', () {
    test('opening a chat fetches the newest page and records the run', () async {
      final server = FakeServer(120);
      final sync = ChatSync(store, server, pageSize: 50);

      await sync.syncLatest(1);

      expect(await store.ranges(1), [(low: 71, high: 120)]);
      expect(await storedSeqs(), [for (var s = 71; s <= 120; s++) s]);
      expect(server.calls, ['before end']);
    });

    test('a short chat is complete from seq 1', () async {
      final sync = ChatSync(store, FakeServer(3), pageSize: 50);
      await sync.syncLatest(1);
      expect(await store.ranges(1), [(low: 1, high: 3)]);
    });

    test('a little behind: fills the pages between, leaving one run', () async {
      final server = FakeServer(100);
      final sync = ChatSync(store, server, pageSize: 50, catchUpLimit: 300);
      await sync.syncLatest(1); // 51..100

      server.count = 260; // 160 new messages while away
      server.calls.clear();
      await sync.syncLatest(1);

      // The newest page is 211..260; 101..210 come in three requests, the
      // last one only as big as needed.
      expect(await store.ranges(1), [(low: 51, high: 260)]);
      expect(await storedSeqs(), [for (var s = 51; s <= 260; s++) s]);
      expect(server.calls, ['before end', 'after 100', 'after 150', 'after 200']);
      expect(server.limits.last, 10);
    });

    test('far behind: keeps just the newest page and leaves a gap', () async {
      final server = FakeServer(100);
      final sync = ChatSync(store, server, pageSize: 50, catchUpLimit: 300);
      await sync.syncLatest(1); // 51..100

      server.count = 10000;
      server.calls.clear();
      await sync.syncLatest(1);

      expect(await store.ranges(1), [(low: 9951, high: 10000), (low: 51, high: 100)]);
      expect(server.calls, ['before end']); // not 198 pages
    });

    test('scrolling up loads the page before, and joins up across a gap', () async {
      final server = FakeServer(100);
      final sync = ChatSync(store, server, pageSize: 50, catchUpLimit: 10);
      await sync.syncLatest(1); // 51..100
      server.count = 200;
      await sync.syncLatest(1); // 151..200, gap 101..150

      expect(await sync.loadOlder(1), isTrue); // 101..150: touches 51..100
      expect(await store.ranges(1), [(low: 51, high: 200)]);
      expect(await sync.loadOlder(1), isTrue); // 1..50
      expect(await store.ranges(1), [(low: 1, high: 200)]);
      expect(await sync.loadOlder(1), isFalse); // the start
    });

    test('a new-message event fetches only what is missing', () async {
      final server = FakeServer(60);
      final sync = ChatSync(store, server, pageSize: 50);
      await sync.syncLatest(1); // 11..60

      server.count = 62;
      server.calls.clear();
      await sync.onNewMessage(1, 62);
      await sync.onNewMessage(1, 61); // already here: no request

      expect(await store.ranges(1), [(low: 11, high: 62)]);
      expect(server.calls, ['after 60']);
    });

    test('work on one chat runs one step at a time', () async {
      final server = FakeServer(80);
      final sync = ChatSync(store, server, pageSize: 50);
      await Future.wait([sync.syncLatest(1), sync.onNewMessage(1, 80), sync.syncLatest(1)]);
      expect(await store.ranges(1), [(low: 31, high: 80)]);
      // The event waited for the first sync and found nothing missing.
      expect(server.calls, ['before end', 'before end']);
    });

    test('re-fetches copies older than the photo-link lifetime', () async {
      final server = FakeServer(10);
      final sync = ChatSync(store, server, pageSize: 50);
      await sync.syncLatest(1);

      now = now.add(const Duration(minutes: 30));
      server.calls.clear();
      await sync.refreshStale(1, 1, 10);
      expect(server.calls, isEmpty); // still fresh

      now = now.add(const Duration(minutes: 30));
      await sync.refreshStale(1, 4, 6);
      expect(server.calls, ['after 3']);
      expect(await store.staleSeqs(1, 4, 6, const Duration(minutes: 50)), isEmpty);
    });
  });

  group('ranges', () {
    test('merge when they overlap or touch, stay apart across a gap', () async {
      await store.addRange(1, 10, 20);
      await store.addRange(1, 30, 40);
      expect(await store.ranges(1), [(low: 30, high: 40), (low: 10, high: 20)]);
      await store.addRange(1, 21, 29); // touches both
      expect(await store.ranges(1), [(low: 10, high: 40)]);
      await store.addRange(2, 1, 5); // another conversation
      expect(await store.ranges(1), [(low: 10, high: 40)]);
    });
  });

  group('search', () {
    Future<void> seed(Map<int, String> bodies) async {
      final server = FakeServer(bodies.length)..bodies.addAll(bodies);
      await ChatSync(store, server).syncLatest(1);
    }

    test('finds every word, as prefixes, newest first, with matches marked', () async {
      await seed({1: 'Photos from the beach', 2: 'lunch tomorrow?', 3: 'the beach photo is great'});
      final hits = await store.search('beach photo');
      expect(hits.map((h) => h.message.seq), [3, 1]);
      expect(hits.first.snippet, contains('${MessageStore.matchStart}photo${MessageStore.matchEnd}'));
      expect((await store.search('lunch')).single.message.seq, 2);
      expect(await store.search('dinner'), isEmpty);
    });

    test('ignores accents and case, and treats operators as plain words', () async {
      await seed({1: 'Café at NINE', 2: 'this OR that', 3: 'quote "here"'});
      expect((await store.search('cafe nine')).single.message.seq, 1);
      expect((await store.search('OR')).single.message.seq, 2);
      expect((await store.search('"here')).single.message.seq, 3);
      expect(await store.search('   '), isEmpty);
    });

    test('a fresh copy of a message replaces its old text in the index', () async {
      final server = FakeServer(1)..bodies[1] = 'old words';
      final sync = ChatSync(store, server);
      await sync.syncLatest(1);
      server.bodies[1] = 'new words';
      now = now.add(const Duration(hours: 1));
      await sync.refreshStale(1, 1, 1);
      expect(await store.search('old'), isEmpty);
      expect((await store.search('new')).single.message.seq, 1);
    });

    test('can be limited to one conversation', () async {
      await seed({1: 'hello there'});
      expect(await store.search('hello', conversationId: 1), hasLength(1));
      expect(await store.search('hello', conversationId: 2), isEmpty);
    });
  });

  test('the stored message is exactly what the server sent', () async {
    await ChatSync(store, FakeServer(1)).syncLatest(1);
    final stored = (await store.watchFrom(1, 0).first).single;
    expect(jsonDecode(stored.json), {'seq': 1, 'body': 'message 1'});
  });

  test('a stored message can be found by id and its JSON replaced in place', () async {
    await ChatSync(store, FakeServer(3)).syncLatest(1);
    final stored = await store.byMessageId(1, 1002);
    expect(stored?.seq, 2);
    await store.updateJson(1, 1002, jsonEncode({'seq': 2, 'body': 'message 2', 'reactions': ['x']}));
    expect(jsonDecode((await store.byMessageId(1, 1002))!.json)['reactions'], ['x']);
    expect(await store.byMessageId(1, 9999), isNull);
    await store.updateJson(1, 9999, '{}'); // not here: nothing happens
  });

  test('clear forgets everything', () async {
    await ChatSync(store, FakeServer(5)).syncLatest(1);
    await store.clear();
    expect(await storedSeqs(), isEmpty);
    expect(await store.ranges(1), isEmpty);
    expect(await store.search('message'), isEmpty);
  });
}
