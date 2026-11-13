import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_media/shared_media.dart';

/// "New post": text plus up to ten photos or videos, which upload while you
/// type. Used for the feed and for posting in a community; [draftKey] keeps
/// each one's attachments apart. [onPost] gets the text and the uploaded
/// files' ids once everything's ready.
Future<void> showComposePostDialog(
  BuildContext context, {
  required MediaDraftKey draftKey,
  required void Function(String body, List<int> mediaIds) onPost,
  String title = 'New post',
  String? hint,
}) {
  final controller = TextEditingController();
  return showDialog(
    context: context,
    builder: (dialogContext) => ComposePostDialog(
      draftKey: draftKey,
      controller: controller,
      title: title,
      hint: hint,
      onPost: (body, mediaIds) {
        onPost(body, mediaIds);
        Navigator.of(dialogContext).pop();
      },
    ),
  ).whenComplete(controller.dispose);
}

class ComposePostDialog extends ConsumerStatefulWidget {
  const ComposePostDialog({
    super.key,
    required this.draftKey,
    required this.controller,
    required this.onPost,
    this.title = 'New post',
    this.hint,
  });

  final MediaDraftKey draftKey;
  final TextEditingController controller;
  final void Function(String body, List<int> mediaIds) onPost;
  final String title;

  /// A line under the box (the feed explains the fan-out timing there).
  final String? hint;

  @override
  ConsumerState<ComposePostDialog> createState() => _ComposePostDialogState();
}

class _ComposePostDialogState extends ConsumerState<ComposePostDialog> {
  @override
  Widget build(BuildContext context) {
    // Watching keeps the draft alive while the dialog is open; closing the
    // dialog (posting or cancelling) disposes it.
    final draft = ref.watch(mediaDraftProvider(widget.draftKey));
    final mediaIds = draft.mediaIds; // null while anything is uploading or failed
    final hasContent = widget.controller.text.trim().isNotEmpty || draft.items.isNotEmpty;

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: widget.controller,
            maxLines: 4,
            decoration: const InputDecoration(labelText: "What's happening?", border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          ComposerAttachments(draftKey: widget.draftKey),
          if (widget.hint != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(widget.hint!)),
        ],
      ),
      actions: [
        AddMediaButton(draftKey: widget.draftKey),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: !hasContent || mediaIds == null ? null : () => widget.onPost(widget.controller.text, mediaIds),
          child: Text(draft.isPreparing
              ? 'Compressing…'
              : draft.isUploading
                  ? 'Uploading…'
                  : 'Post'),
        ),
      ],
    );
  }
}
