import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Runs before every test file. Sign-in keeps its tokens in secure storage,
/// a platform plugin that doesn't exist under `flutter test` (a read would
/// wait forever); this swaps it for an empty in-memory store, so every test
/// starts signed out.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  FlutterSecureStorage.setMockInitialValues({});
  await testMain();
}
