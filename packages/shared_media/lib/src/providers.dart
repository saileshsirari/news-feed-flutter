import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/media_api.dart';
import 'data/media_upload_service.dart';
import 'data/media_uploader.dart';
import 'picking/media_picker.dart';
import 'processing/video_preparer.dart';

/// The one thing an app must supply: which server, as which user. E.g.
///
///     mediaApiProvider.overrideWith((ref) => HttpMediaApi(
///           baseUrl: ref.watch(appConfigProvider).apiBaseUrl,
///           userId: ref.watch(currentUserProvider).requireValue!.id,
///         ))
final mediaApiProvider = Provider<MediaApi>(
  (ref) => throw UnimplementedError('Override mediaApiProvider in the app\'s ProviderScope'),
);

final mediaUploaderProvider = Provider<MediaUploader>((ref) => MediaUploader());

final mediaUploadServiceProvider = Provider<MediaUploadService>(
  (ref) => MediaUploadService(ref.watch(mediaApiProvider), ref.watch(mediaUploaderProvider)),
);

/// Overridable so widget tests can "pick" without the platform plugin.
final mediaPickerProvider = Provider<MediaPicker>((ref) => MediaPicker());

/// Compresses phone videos before upload; overridable for tests.
final videoPreparerProvider = Provider<VideoPreparer>((ref) => VideoPreparer());
