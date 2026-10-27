import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import '../data/services/api_service.dart';

/// One group call — a thin wrapper around a LiveKit [Room], not a chat-style
/// view model with its own state machine. [Room] is already a ChangeNotifier
/// that fires on every participant/track change (see its RoomEvent handler),
/// so rather than mirror that into separate fields here, this just forwards
/// Room's own notifications: the UI watches CallViewModel and reads
/// `room.localParticipant` / `room.remoteParticipants` directly off it.
class CallViewModel extends ChangeNotifier {
  final ApiService _api;
  final int conversationId;
  final int currentUserId;

  CallViewModel(this._api, {required this.conversationId, required this.currentUserId}) {
    _connect();
  }

  Room? room;
  bool isConnecting = true;
  String? error;
  bool isTogglingRecording = false;
  // Masks room.isRecording right after our own toggle succeeds. LiveKit's
  // RoomRecordingStatusChanged push lags several seconds behind the actual
  // API call — Room Composite Egress has to tear down a headless-Chrome
  // pipeline and finalize the file before the server flips the flag — so
  // waiting on it made the stop button look broken even though the
  // recording had genuinely stopped server-side. Cleared the moment the
  // real event arrives, so it never drifts from the true state for long,
  // and still picks up another participant's toggle correctly.
  bool? _optimisticIsRecording;

  Future<void> _connect() async {
    try {
      // Both requested up front even though the call starts audio-only
      // (see toggleCamera) — asking again mid-call for camera would mean a
      // second OS permission dialog interrupting an already-joined call.
      final statuses = await [Permission.microphone, Permission.camera].request();
      if (statuses[Permission.microphone] != PermissionStatus.granted) {
        throw Exception('Microphone permission is required for a call');
      }

      final callToken = await _api.getCallToken(conversationId, currentUserId);
      final newRoom = Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));
      // Forward Room's own change notifications as this view model's —
      // simplest way for the UI to watch just CallViewModel and still
      // rebuild on every participant/track event Room already tracks.
      newRoom.addListener(notifyListeners);
      // The real signal, once it does arrive, always wins over our guess.
      newRoom.events.listen((event) {
        if (event is RoomRecordingStatusChanged) {
          _optimisticIsRecording = null;
          notifyListeners();
        }
      });
      await newRoom.connect(callToken.url, callToken.token);
      await newRoom.localParticipant?.setMicrophoneEnabled(true);

      room = newRoom;
      isConnecting = false;
      notifyListeners();
    } catch (e) {
      isConnecting = false;
      error = 'Couldn\'t join call: $e';
      notifyListeners();
    }
  }

  bool get isMicEnabled => room?.localParticipant?.isMicrophoneEnabled() ?? false;
  bool get isCameraEnabled => room?.localParticipant?.isCameraEnabled() ?? false;
  // The optimistic guess wins until the real room.isRecording push (see
  // RoomRecordingStatusChanged above) confirms it — so someone else's
  // toggle (no optimistic guess of ours in play) still shows up correctly,
  // it just does so on LiveKit's timeline instead of ours.
  bool get isRecording => _optimisticIsRecording ?? room?.isRecording ?? false;

  /// Toggles recording for everyone in the call, not just the local view —
  /// same "any participant" access control as the call itself. The button
  /// disables itself for the round trip so a slow network can't make it look
  /// like double-tapping does nothing. Left to the caller to catch/display:
  /// a failed toggle shouldn't blow away the call screen the way the
  /// join-time `error` field does.
  Future<void> toggleRecording() async {
    if (isTogglingRecording) return;
    final wasRecording = isRecording;
    isTogglingRecording = true;
    notifyListeners();
    try {
      if (wasRecording) {
        await _api.stopRecording(conversationId, currentUserId);
      } else {
        await _api.startRecording(conversationId, currentUserId);
      }
      _optimisticIsRecording = !wasRecording;
    } finally {
      isTogglingRecording = false;
      notifyListeners();
    }
  }

  Future<void> toggleMic() async {
    final participant = room?.localParticipant;
    if (participant == null) return;
    await participant.setMicrophoneEnabled(!isMicEnabled);
  }

  Future<void> toggleCamera() async {
    final participant = room?.localParticipant;
    if (participant == null) return;
    await participant.setCameraEnabled(!isCameraEnabled);
  }

  Future<void> leave() async {
    await room?.disconnect();
  }

  @override
  void dispose() {
    room?.removeListener(notifyListeners);
    // Fire-and-forget: dispose() itself can't be awaited by ChangeNotifier's
    // contract, and the room is going away regardless of whether this
    // finishes before the widget tree unmounts.
    room?.dispose();
    super.dispose();
  }
}
