import 'package:flutter/material.dart';

import '../models/models.dart';

/// The box at the bottom of the comments sheet, with "Replying to @name ✕"
/// above it while replying. Focuses itself when a reply starts. The text
/// clears only once [onSend] says it went, so a failed send loses nothing.
class CommentComposer extends StatefulWidget {
  const CommentComposer({
    super.key,
    required this.replyTo,
    required this.isSending,
    required this.isReply,
    required this.onSend,
    required this.onCancelReply,
  });

  final PostComment? replyTo;
  final bool isSending;

  /// Replying to someone, or in a thread: "Add a reply" rather than "Add a comment".
  final bool isReply;
  final Future<bool> Function(String text) onSend;
  final VoidCallback onCancelReply;

  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer> {
  final _input = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(CommentComposer old) {
    super.didUpdateWidget(old);
    // Tapping Reply on a comment puts the cursor in the box.
    if (widget.replyTo != null && widget.replyTo?.id != old.replyTo?.id) _focus.requestFocus();
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_input.text.trim().isEmpty || widget.isSending) return;
    if (await widget.onSend(_input.text) && mounted) _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final replyTo = widget.replyTo;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (replyTo != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text('Replying to @${replyTo.authorUsername}', style: Theme.of(context).textTheme.labelMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Cancel reply',
                  onPressed: widget.onCancelReply,
                ),
              ],
            ),
          ),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + MediaQuery.of(context).viewInsets.bottom),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('comment-input'),
                    controller: _input,
                    focusNode: _focus,
                    maxLength: 2000,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: replyTo != null || widget.isReply ? 'Add a reply' : 'Add a comment',
                      border: const OutlineInputBorder(),
                      counterText: '',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  tooltip: 'Post comment',
                  onPressed: _input.text.trim().isEmpty || widget.isSending ? null : _send,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
