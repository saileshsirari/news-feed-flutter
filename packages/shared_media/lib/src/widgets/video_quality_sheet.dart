import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/media_limits.dart';
import '../settings/media_settings.dart';
import '../settings/video_upload_quality.dart';

/// Lets the user choose how videos are compressed, showing what each
/// choice costs in size and upload time. Saves the choice when they
/// confirm; returns it, or null if they dismissed the sheet.
///
/// [firstTime] is for the prompt on someone's first video: it explains that
/// this can be changed later, where.
Future<VideoUploadQuality?> showVideoQualitySheet(BuildContext context, {bool firstTime = false}) =>
    showModalBottomSheet<VideoUploadQuality>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _VideoQualitySheet(firstTime: firstTime),
    );

/// A row for an app's settings screen: the current choice, tap to change.
/// Disabled in a browser, which always uploads videos as they are.
class VideoQualitySettingTile extends ConsumerWidget {
  const VideoQualitySettingTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) {
      return const ListTile(
        enabled: false,
        leading: Icon(Icons.high_quality_outlined),
        title: Text('Video upload quality'),
        subtitle: Text('Browsers upload videos as they are; choose a quality in the phone app'),
      );
    }
    final quality = ref.watch(mediaSettingsProvider).value?.videoQuality ?? VideoUploadQuality.recommended;
    return ListTile(
      leading: const Icon(Icons.high_quality_outlined),
      title: const Text('Video upload quality'),
      subtitle: Text('${quality.label} · ${quality.description}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showVideoQualitySheet(context),
    );
  }
}

class _VideoQualitySheet extends ConsumerStatefulWidget {
  const _VideoQualitySheet({required this.firstTime});

  final bool firstTime;

  @override
  ConsumerState<_VideoQualitySheet> createState() => _VideoQualitySheetState();
}

class _VideoQualitySheetState extends ConsumerState<_VideoQualitySheet> {
  /// Estimates are for a clip this long: the longest allowed.
  static const _clipSeconds = MediaLimits.maxVideoDurationMs ~/ 1000;

  late VideoUploadQuality _selected =
      ref.read(mediaSettingsProvider).value?.videoQuality ?? VideoUploadQuality.recommended;

  Future<void> _save() async {
    await ref.read(mediaSettingsProvider.notifier).setVideoQuality(_selected);
    if (mounted) Navigator.of(context).pop(_selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The options scroll if the screen is short; the button stays put.
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Video upload quality', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Smaller files upload faster. Estimates for a $_clipSeconds-second clip on mobile data '
              '(${VideoUploadQuality.typicalUploadMbitPerSecond.round()} Mbit/s).',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: RadioGroup<VideoUploadQuality>(
                  groupValue: _selected,
                  onChanged: (quality) => setState(() => _selected = quality ?? _selected),
                  child: Column(children: [for (final quality in VideoUploadQuality.values) _option(quality, theme)]),
                ),
              ),
            ),
            if (widget.firstTime)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('You can change this any time in Settings.', style: theme.textTheme.bodySmall),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _save, child: Text(widget.firstTime ? 'Continue' : 'Save')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(VideoUploadQuality quality, ThemeData theme) {
    final megabytes = quality.approxMegabytes(_clipSeconds).round();
    // How long a clip fits the server's limit, at this quality.
    final fitsSeconds = (MediaLimits.maxVideoBytes / (1024 * 1024) * 8 / quality.approxMbitPerSecond).floor();
    final estimate = fitsSeconds < _clipSeconds
        ? '≈ $megabytes MB · clips over ${fitsSeconds}s are too large to upload'
        : '≈ $megabytes MB · about ${quality.approxUploadSeconds(_clipSeconds)} s to upload';
    return RadioListTile<VideoUploadQuality>(
      value: quality,
      contentPadding: EdgeInsets.zero,
      title: Text(quality == VideoUploadQuality.recommended ? '${quality.label} (recommended)' : quality.label),
      subtitle: Text('${quality.description}\n$estimate'),
      isThreeLine: true,
    );
  }
}
