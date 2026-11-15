import 'dart:async';

import 'package:app_core/config/app_config.dart';
import 'package:app_core/data/services/app_socket.dart';

/// A socket that never connects; tests push events into [controller] by
/// hand. Use with `socketProvider.overrideWith((ref, userId) => socket)`.
class FakeSocket extends AppSocket {
  FakeSocket() : super(1, AppConfig(apiBaseUrl: Uri.parse('https://example.test')));
  final controller = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
}
