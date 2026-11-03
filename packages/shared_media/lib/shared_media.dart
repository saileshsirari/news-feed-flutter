/// Images and video for posts and chat messages: picking, uploading, and
/// (from phase 2) showing them. The public API is what's exported here;
/// everything under src/ is private to the package.
library;

export 'src/data/media_api.dart' show HttpMediaApi, MediaApi, MediaApiException, UploadTicket;
export 'src/data/media_upload_service.dart' show MediaUploadService;
export 'src/data/media_uploader.dart' show MediaUploader, UploadFailedException;
export 'src/draft/media_draft.dart' show DraftItem, DraftItemStatus, MediaDraftKey, MediaDraftState;
export 'src/draft/media_draft_notifier.dart' show MediaDraftNotifier, mediaDraftProvider;
export 'src/models/media_attachment.dart' show MediaAttachment, MediaKind;
export 'src/models/media_limits.dart' show MediaLimits;
export 'src/models/picked_media.dart' show PickedMedia;
export 'src/providers.dart' show mediaApiProvider, mediaUploadServiceProvider, mediaUploaderProvider;
