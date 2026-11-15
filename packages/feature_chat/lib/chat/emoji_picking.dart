import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

/// Every emoji, in categories, with search, skin tones and recently used
/// (emoji_picker_flutter, MIT). Returns the one picked, or null.
Future<String?> pickEmoji(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: 340,
          child: EmojiPicker(
            onEmojiSelected: (_, emoji) => Navigator.of(context).pop(emoji.emoji),
            config: const Config(height: 340),
          ),
        ),
      ),
    );

/// The picker under the message box: tapping an emoji types it where the
/// cursor is. Mostly for the web (phones also have the keyboard's emojis).
Future<void> showEmojiKeyboard(BuildContext context, TextEditingController controller) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: 340,
          child: EmojiPicker(textEditingController: controller, config: const Config(height: 340)),
        ),
      ),
    );
