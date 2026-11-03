import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:news_feed_flutter/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('changing the video quality in Settings is saved', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: SettingsScreen())));
    await tester.pumpAndSettle();

    expect(find.text('540p · Looks good on phones'), findsOneWidget);

    await tester.tap(find.text('Video upload quality'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('720p'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('720p · HD'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('shared_media.videoUploadQuality'), 'p720');
  });
}
