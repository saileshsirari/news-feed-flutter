import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'call_notifier.dart';

/// A group call for one conversation — LiveKit room name == "conversation-
/// `<id>`" (see chatService.createCallToken), so anyone with the call-token
/// endpoint's OK (i.e. any participant) can join the same room independently;
/// there's no separate "who's currently in the call" invite step.
///
/// Compose/Android: ≈ collecting `hiltViewModel<CallViewModel>(key = id)`'s
/// state. Every Room change bumps CallState.roomRevision, so this rebuilds
/// and the grid and buttons below re-read the Room.
class CallScreen extends ConsumerWidget {
  final int conversationId;
  final String title;
  const CallScreen({super.key, required this.conversationId, required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.watch(callProvider(conversationId));
    final notifier = ref.read(callProvider(conversationId).notifier);
    final room = vm.room;

    // Everyone else hung up (or nobody answered): say so, then close.
    ref.listen(callProvider(conversationId).select((s) => s.endedReason), (_, reason) {
      if (reason == null) return;
      Future<void>.delayed(const Duration(milliseconds: 1500), () {
        if (context.mounted) Navigator.of(context).maybePop();
      });
    });

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
        actions: [
          if (vm.isRecording)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: _RecordingBadge()),
            ),
        ],
      ),
      body: SafeArea(
        child: vm.endedReason != null
            ? Center(
                child: Text(
                  vm.endedReason!,
                  key: const Key('call-ended'),
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
              )
            : vm.error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(vm.error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                ),
              )
            : vm.isConnecting || room == null
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    children: [
                      _ParticipantGrid(room: room),
                      // The browser blocked sound until a click: ask for one.
                      if (!vm.canPlayAudio)
                        Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: FilledButton.icon(
                              key: const Key('turn-on-sound'),
                              onPressed: notifier.startAudio,
                              icon: const Icon(Icons.volume_up),
                              label: const Text('Tap to turn on sound'),
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
      bottomNavigationBar: room == null || vm.endedReason != null
          ? null
          : SafeArea(child: _CallControls(vm: vm, notifier: notifier)),
    );
  }
}

class _RecordingBadge extends StatelessWidget {
  const _RecordingBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fiber_manual_record, color: Colors.white, size: 12),
          SizedBox(width: 4),
          Text('REC', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _ParticipantGrid extends StatelessWidget {
  final Room room;
  const _ParticipantGrid({required this.room});

  @override
  Widget build(BuildContext context) {
    final localParticipant = room.localParticipant;
    final participants = <Participant>[
      if (localParticipant != null) localParticipant,
      ...room.remoteParticipants.values,
    ];

    if (participants.isEmpty) {
      return const Center(child: Text('Connecting...', style: TextStyle(color: Colors.white70)));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: participants.length <= 2 ? 1 : 2,
        childAspectRatio: 3 / 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: participants.length,
      itemBuilder: (context, index) => _ParticipantTile(
        participant: participants[index],
        isLocal: participants[index] == localParticipant,
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final Participant participant;
  final bool isLocal;
  const _ParticipantTile({required this.participant, required this.isLocal});

  @override
  Widget build(BuildContext context) {
    final videoPublications = participant.videoTrackPublications;
    final videoTrack = videoPublications.isNotEmpty ? videoPublications.first.track : null;

    return Container(
      decoration: BoxDecoration(color: Colors.grey.shade900, borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (videoTrack is VideoTrack)
            VideoTrackRenderer(
              videoTrack,
              mirrorMode: isLocal ? VideoViewMirrorMode.mirror : VideoViewMirrorMode.off,
            )
          else
            Center(
              child: CircleAvatar(
                radius: 32,
                child: Text(
                  participant.name.isNotEmpty ? participant.name[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
          Positioned(
            left: 8,
            bottom: 8,
            right: 8,
            child: Row(
              children: [
                if (!participant.isMicrophoneEnabled())
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.mic_off, color: Colors.white, size: 16),
                  ),
                Flexible(
                  child: Text(
                    isLocal ? '${participant.name} (you)' : participant.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CallControls extends StatelessWidget {
  final CallState vm;
  final CallNotifier notifier;
  const _CallControls({required this.vm, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ControlButton(
            icon: vm.isMicEnabled ? Icons.mic : Icons.mic_off,
            onPressed: notifier.toggleMic,
          ),
          _ControlButton(
            icon: vm.isCameraEnabled ? Icons.videocam : Icons.videocam_off,
            onPressed: notifier.toggleCamera,
          ),
          _ControlButton(
            icon: vm.isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
            backgroundColor: vm.isRecording ? Colors.red : null,
            onPressed: vm.isTogglingRecording
                ? null
                : () async {
                    try {
                      await notifier.toggleRecording();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Recording failed: $e')),
                        );
                      }
                    }
                  },
          ),
          _ControlButton(
            icon: Icons.call_end,
            backgroundColor: Colors.red,
            onPressed: () async {
              await notifier.leave();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  const _ControlButton({required this.icon, required this.onPressed, this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 28,
      backgroundColor: backgroundColor ?? Colors.grey.shade800,
      child: IconButton(icon: Icon(icon, color: Colors.white), onPressed: onPressed),
    );
  }
}
