import 'package:flutter/material.dart';
import 'package:shared_media/shared_media.dart';
import 'notifications_setting_tile.dart';

/// App settings. Each feature contributes its own rows; the media package's
/// video quality is the first.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SectionHeader('Notifications'),
          const NotificationsSettingTile(),
          _SectionHeader('Uploads'),
          const VideoQualitySettingTile(),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
