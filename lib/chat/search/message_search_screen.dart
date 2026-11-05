import 'dart:async';

import 'package:chat_store/chat_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../session/current_user_provider.dart';
import '../conversation_screen.dart';
import '../conversations_notifier.dart';
import '../local/local_chat.dart';

/// Searches chat messages kept on this device (chat_store's full-text
/// index), never the server: the same for end-to-end encrypted chats, whose
/// text the server can't read anyway. So it finds what this device has
/// synced: a chat you haven't scrolled back through may have older matches
/// it doesn't know about yet.
class MessageSearchScreen extends ConsumerStatefulWidget {
  const MessageSearchScreen({super.key});

  @override
  ConsumerState<MessageSearchScreen> createState() => _MessageSearchScreenState();
}

class _MessageSearchScreenState extends ConsumerState<MessageSearchScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<SearchHit> _hits = const [];
  String _searched = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// Waits for a pause in typing, so each keystroke isn't a search.
  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(text));
  }

  Future<void> _search(String text) async {
    final userId = ref.read(currentUserProvider).requireValue!.id;
    final hits = await ref.read(messageStoreProvider(userId)).search(text);
    if (!mounted) return;
    setState(() {
      _hits = hits;
      _searched = text.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    final conversations = {for (final c in ref.watch(conversationsProvider).conversations) c.id: c};
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const Key('message-search'),
          controller: _query,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search messages', border: InputBorder.none),
          onChanged: _onChanged,
          onSubmitted: _search,
        ),
      ),
      body: _searched.isEmpty
          ? const _Hint('Searches the messages on this device.')
          : _hits.isEmpty
          ? _Hint('No messages on this device match "$_searched".')
          : ListView.separated(
              itemCount: _hits.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _HitRow(_hits[index], conversations[_hits[index].message.conversationId]),
            ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
  );
}

class _HitRow extends StatelessWidget {
  const _HitRow(this.hit, this.conversation);

  final SearchHit hit;
  final ConversationSummary? conversation;

  @override
  Widget build(BuildContext context) {
    final message = chatMessageFrom(hit.message);
    final title = conversation?.displayTitle() ?? 'Chat';
    final sent = DateTime.fromMillisecondsSinceEpoch(message.createdAt);
    return ListTile(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '${message.senderUsername}: '),
            ...highlighted(hit.snippet),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(MaterialLocalizations.of(context).formatShortDate(sent)),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConversationScreen(
            conversationId: message.conversationId,
            title: title,
            otherUserId: conversation?.otherUserId,
          ),
        ),
      ),
    );
  }
}

/// The snippet's matched words in bold (chat_store marks them).
List<TextSpan> highlighted(String snippet) {
  final spans = <TextSpan>[];
  var rest = snippet;
  while (rest.isNotEmpty) {
    final start = rest.indexOf(MessageStore.matchStart);
    if (start < 0) {
      spans.add(TextSpan(text: rest));
      break;
    }
    if (start > 0) spans.add(TextSpan(text: rest.substring(0, start)));
    final end = rest.indexOf(MessageStore.matchEnd, start);
    final stop = end < 0 ? rest.length : end;
    spans.add(
      TextSpan(
        text: rest.substring(start + 1, stop),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
    rest = end < 0 ? '' : rest.substring(end + 1);
  }
  return spans;
}
