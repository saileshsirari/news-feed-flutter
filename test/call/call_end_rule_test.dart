import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:news_feed_flutter/call/call_end_rule.dart';

void main() {
  late List<String> ends;
  CallEndRule rule() => CallEndRule(onEnd: ends.add);

  setUp(() => ends = []);

  test('1:1: the other person hangs up, so the call ends for me too', () {
    fakeAsync((time) {
      final r = rule()..start(1);
      r.othersChanged(0);
      time.elapse(const Duration(seconds: 2));
      expect(ends, isEmpty); // a moment's grace
      time.elapse(const Duration(seconds: 2));
      expect(ends, [CallEndRule.ended]);
    });
  });

  test('a quick drop-and-rejoin (network blip) doesn\'t end it', () {
    fakeAsync((time) {
      final r = rule()..start(1);
      r.othersChanged(0);
      time.elapse(const Duration(seconds: 2));
      r.othersChanged(1);
      time.elapse(const Duration(minutes: 5));
      expect(ends, isEmpty);
    });
  });

  test('group: carries on while anyone else is there, ends when I\'m alone', () {
    fakeAsync((time) {
      final r = rule()..start(2);
      r.othersChanged(1); // one left
      time.elapse(const Duration(minutes: 1));
      expect(ends, isEmpty);
      r.othersChanged(0); // the last one left
      time.elapse(const Duration(seconds: 4));
      expect(ends, [CallEndRule.ended]);
    });
  });

  test('nobody answers within a minute: no answer', () {
    fakeAsync((time) {
      rule().start(0);
      time.elapse(const Duration(seconds: 59));
      expect(ends, isEmpty);
      time.elapse(const Duration(seconds: 2));
      expect(ends, [CallEndRule.noAnswer]);
    });
  });

  test('someone answers: no "no answer"; losing the connection ends it once', () {
    fakeAsync((time) {
      final r = rule()..start(0);
      r.othersChanged(1);
      time.elapse(const Duration(minutes: 2));
      expect(ends, isEmpty);
      r.disconnected();
      r.disconnected();
      r.othersChanged(0);
      time.elapse(const Duration(seconds: 10));
      expect(ends, [CallEndRule.ended]);
    });
  });

  test('hanging up myself cancels everything', () {
    fakeAsync((time) {
      final r = rule()..start(0);
      r.dispose();
      time.elapse(const Duration(minutes: 2));
      expect(ends, isEmpty);
    });
  });
}
