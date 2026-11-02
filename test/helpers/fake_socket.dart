import 'dart:async';

import 'package:news_feed_flutter/config/app_config.dart';
import 'package:news_feed_flutter/data/services/app_socket.dart';

/// A socket that never connects; tests push events into [controller] by
/// hand. Use with `socketProvider.overrideWith((ref, userId) => socket)`.
class FakeSocket extends AppSocket {
  FakeSocket() : super(1, AppConfig(apiBaseUrl: Uri.parse('https://example.test')));
  final controller = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
}
