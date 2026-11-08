import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../push/push_registration.dart';
import '../session/current_user_provider.dart';

/// "Notifications" on or off for this device. Turning it on shows the
/// system's permission prompt (browsers only allow that after a click,
/// which is why it's a switch here rather than a prompt at startup).
class NotificationsSettingTile extends ConsumerStatefulWidget {
  const NotificationsSettingTile({super.key});

  @override
  ConsumerState<NotificationsSettingTile> createState() => _NotificationsSettingTileState();
}

class _NotificationsSettingTileState extends ConsumerState<NotificationsSettingTile> {
  bool? _on;
  bool _busy = false;

  /// Settings is only reachable when signed in; null just in case.
  int? get _signedInUserId => ref.read(currentUserProvider).value?.id;
  int get _userId => _signedInUserId!;

  @override
  void initState() {
    super.initState();
    final userId = _signedInUserId;
    if (userId == null) return;
    ref.read(pushRegistrationProvider).isOn(userId).then((on) {
      if (mounted) setState(() => _on = on);
    });
  }

  Future<void> _toggle(bool turnOn) async {
    final push = ref.read(pushRegistrationProvider);
    setState(() => _busy = true);
    String? message;
    if (turnOn) {
      final result = await push.enable(_userId);
      message = switch (result) {
        PushEnableResult.on => null,
        PushEnableResult.denied => 'Notifications are blocked. Allow them in the browser or phone settings.',
        PushEnableResult.unsupported => 'This device can\'t receive notifications from the app yet.',
        PushEnableResult.needsAccount => 'Notifications need a signed-in account, not a test account.',
        PushEnableResult.notConfigured => 'The server isn\'t set up to send notifications here yet.',
        PushEnableResult.failed => 'Couldn\'t turn notifications on. Try again.',
      };
    } else {
      await push.disable(_userId);
    }
    final on = await push.isOn(_userId);
    if (!mounted) return;
    setState(() {
      _on = on;
      _busy = false;
    });
    if (message != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_signedInUserId == null) return const SizedBox.shrink();
    return SwitchListTile(
      key: const Key('notifications-switch'),
      secondary: const Icon(Icons.notifications_outlined),
      title: const Text('Notifications'),
      subtitle: const Text('New messages when the app is closed or in the background'),
      value: _on ?? false,
      onChanged: _on == null || _busy ? null : _toggle,
    );
  }
}
