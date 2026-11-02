import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import '../data/services/service_providers.dart';
import '../session/current_user_provider.dart';

/// What CallScreen draws.
///
/// Unlike the chat notifiers' states, this one can't hold everything as
/// immutable data: participants, tracks and mute flags live inside LiveKit's
/// [Room], a mutable object that changes on its own. So the state holds the
/// Room itself plus [roomRevision], a counter bumped every time Room says it
/// changed. The bump is what makes `state = ...` produce a new value, so
/// widgets watching this rebuild and read fresh data off [room].
///
/// Compose/Android: the same problem as wrapping a mutable SDK object (an
/// ExoPlayer, a camera session) in a ViewModel: you expose the object plus
/// a "something changed" tick in your UiState rather than copying all of
/// its internals.
class CallState {
  const CallState({
    this.room,
    this.roomRevision = 0,
    this.isConnecting = true,
    this.error,
    this.isTogglingRecording = false,
    this.optimisticIsRecording,
  });

  final Room? room;
  final int roomRevision;
  final bool isConnecting;
  final String? error;
  final bool isTogglingRecording;

  // Masks room.isRecording right after our own toggle succeeds. LiveKit's
  // RoomRecordingStatusChanged push lags several seconds behind the actual
  // API call — Room Composite Egress has to tear down a headless-Chrome
  // pipeline and finalize the file before the server flips the flag — so
  // waiting on it made the stop button look broken even though the
  // recording had genuinely stopped server-side. Cleared the moment the
  // real event arrives, so it never drifts from the true state for long,
  // and still picks up another participant's toggle correctly.
  final bool? optimisticIsRecording;

  bool get isMicEnabled => room?.localParticipant?.isMicrophoneEnabled() ?? false;
  bool get isCameraEnabled => room?.localParticipant?.isCameraEnabled() ?? false;
  // The optimistic guess wins until the real room.isRecording push (see
  // RoomRecordingStatusChanged in CallNotifier) confirms it — so someone
  // else's toggle (no optimistic guess of ours in play) still shows up
  // correctly, it just does so on LiveKit's timeline instead of ours.
  bool get isRecording => optimisticIsRecording ?? room?.isRecording ?? false;

  /// [error] and [optimisticIsRecording] use a sentinel so they can be
  /// cleared back to null.
  CallState copyWith({
    Room? room,
    int? roomRevision,
    bool? isConnecting,
    Object? error = _keep,
    bool? isTogglingRecording,
    Object? optimisticIsRecording = _keep,
  }) {
    return CallState(
      room: room ?? this.room,
      roomRevision: roomRevision ?? this.roomRevision,
      isConnecting: isConnecting ?? this.isConnecting,
      error: identical(error, _keep) ? this.error : error as String?,
      isTogglingRecording: isTogglingRecording ?? this.isTogglingRecording,
      optimisticIsRecording:
          identical(optimisticIsRecording, _keep) ? this.optimisticIsRecording : optimisticIsRecording as bool?,
    );
  }

  static const _keep = Object();
}

/// One group call — a thin wrapper around a LiveKit [Room], not a chat-style
/// view model with its own state machine: participant/track data is read
/// straight off the Room (see CallState).
///
/// Compose/Android: ≈ `CallViewModel @AssistedInject constructor(
/// @Assisted conversationId: Int)`, with `onCleared()` disposing the Room.
class CallNotifier extends Notifier<CallState> {
  CallNotifier(this.conversationId);

  final int conversationId;
  late int _currentUserId;
  // The connected Room, kept outside `state` too so onDispose can reach it
  // without reading state from a notifier that's being torn down.
  Room? _room;

  @override
  CallState build() {
    // ref.read, not watch: see ConversationNotifier.build.
    _currentUserId = ref.read(currentUserProvider).requireValue!.id;
    // ≈ onCleared(): disposes whichever Room ended up connected (none if we
    // were still connecting — _connect cleans that case up itself).
    ref.onDispose(() {
      _room?.removeListener(_onRoomChanged);
      // Fire-and-forget: onDispose can't be awaited, and the room is going
      // away regardless of whether this finishes before the screen unmounts.
      _room?.dispose();
    });
    _connect();
    return const CallState();
  }

  /// Room's own "I changed" callback, turned into a new state.
  void _onRoomChanged() {
    if (!ref.mounted) return;
    state = state.copyWith(roomRevision: state.roomRevision + 1);
  }

  Future<void> _connect() async {
    Room? newRoom;
    try {
      // Both requested up front even though the call starts audio-only
      // (see toggleCamera) — asking again mid-call for camera would mean a
      // second OS permission dialog interrupting an already-joined call.
      final statuses = await [Permission.microphone, Permission.camera].request();
      if (statuses[Permission.microphone] != PermissionStatus.granted) {
        throw Exception('Microphone permission is required for a call');
      }

      final callToken = await ref.read(apiServiceProvider).getCallToken(conversationId, _currentUserId);
      if (!ref.mounted) return;
      newRoom = Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));
      newRoom.addListener(_onRoomChanged);
      // The real signal, once it does arrive, always wins over our guess.
      newRoom.events.listen((event) {
        if (event is RoomRecordingStatusChanged && ref.mounted) {
          state = state.copyWith(optimisticIsRecording: null);
        }
      });
      await newRoom.connect(callToken.url, callToken.token);
      await newRoom.localParticipant?.setMicrophoneEnabled(true);

      if (!ref.mounted) {
        // The screen closed while we were joining. The old ChangeNotifier
        // kept this Room alive forever in that case; nothing else will
        // dispose it now, so do it here.
        newRoom.removeListener(_onRoomChanged);
        await newRoom.dispose();
        return;
      }
      _room = newRoom;
      state = state.copyWith(room: newRoom, isConnecting: false);
    } catch (e) {
      if (!ref.mounted) {
        await newRoom?.dispose();
        return;
      }
      state = state.copyWith(isConnecting: false, error: 'Couldn\'t join call: $e');
    }
  }

  /// Toggles recording for everyone in the call, not just the local view —
  /// same "any participant" access control as the call itself. The button
  /// disables itself for the round trip so a slow network can't make it look
  /// like double-tapping does nothing. Left to the caller to catch/display:
  /// a failed toggle shouldn't blow away the call screen the way the
  /// join-time `error` field does.
  Future<void> toggleRecording() async {
    if (state.isTogglingRecording) return;
    final wasRecording = state.isRecording;
    state = state.copyWith(isTogglingRecording: true);
    try {
      final api = ref.read(apiServiceProvider);
      if (wasRecording) {
        await api.stopRecording(conversationId, _currentUserId);
      } else {
        await api.startRecording(conversationId, _currentUserId);
      }
      if (ref.mounted) state = state.copyWith(optimisticIsRecording: !wasRecording);
    } finally {
      if (ref.mounted) state = state.copyWith(isTogglingRecording: false);
    }
  }

  // Mic/camera/leave act on the Room directly; Room then notifies
  // _onRoomChanged, which bumps the revision and redraws the buttons.
  Future<void> toggleMic() async {
    final participant = state.room?.localParticipant;
    if (participant == null) return;
    await participant.setMicrophoneEnabled(!state.isMicEnabled);
  }

  Future<void> toggleCamera() async {
    final participant = state.room?.localParticipant;
    if (participant == null) return;
    await participant.setCameraEnabled(!state.isCameraEnabled);
  }

  Future<void> leave() async {
    await state.room?.disconnect();
  }
}

/// One call per conversation; autoDispose disposes the Room when
/// CallScreen closes (≈ ViewModel.onCleared()).
final callProvider = NotifierProvider.autoDispose.family<CallNotifier, CallState, int>(CallNotifier.new);
