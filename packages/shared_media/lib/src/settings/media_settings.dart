import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'video_upload_quality.dart';

class MediaSettings {
  const MediaSettings({this.videoQuality = VideoUploadQuality.recommended, this.hasChosenVideoQuality = false});

  final VideoUploadQuality videoQuality;

  /// False until the user picks a quality themselves, so the first video
  /// they attach can ask once.
  final bool hasChosenVideoQuality;
}

/// The user's media preferences, saved on the device. Here in the package
/// rather than the app so any app built on shared_media gets the same
/// setting (stored under its own keys, see [_qualityKey]).
///
/// Compose/Android: ≈ a DataStore-backed repository exposing a Flow.
class MediaSettingsNotifier extends AsyncNotifier<MediaSettings> {
  static const _qualityKey = 'shared_media.videoUploadQuality';

  @override
  Future<MediaSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = VideoUploadQuality.fromName(prefs.getString(_qualityKey));
    return saved == null ? const MediaSettings() : MediaSettings(videoQuality: saved, hasChosenVideoQuality: true);
  }

  Future<void> setVideoQuality(VideoUploadQuality quality) async {
    // Let the initial load finish first, or it would land afterwards and
    // put back the old value over this one.
    await future;
    state = AsyncData(MediaSettings(videoQuality: quality, hasChosenVideoQuality: true));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_qualityKey, quality.name);
  }
}

final mediaSettingsProvider = AsyncNotifierProvider<MediaSettingsNotifier, MediaSettings>(MediaSettingsNotifier.new);
