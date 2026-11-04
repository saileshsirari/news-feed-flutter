import 'package:flutter_test/flutter_test.dart';
import 'package:news_feed_flutter/chat/message_sender.dart';

// Also run in a browser, where Dart ints are JavaScript numbers (a
// `1 << 32` here once made every web send throw):
//   flutter test --platform chrome test/chat/message_sender_test.dart
void main() {
  test('client message ids are unique and only use characters the server allows', () {
    final ids = List.generate(200, (_) => newClientMessageId(7));
    expect(ids.toSet(), hasLength(200));
    expect(ids, everyElement(matches(RegExp(r'^7-\d+-[a-z0-9]+$'))));
    expect(ids, everyElement(hasLength(lessThanOrEqualTo(64))));
  });
}
