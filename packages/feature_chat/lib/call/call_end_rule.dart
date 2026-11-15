import 'dart:async';

/// When a call should end on its own, as in WhatsApp, Teams or Meet:
///
///   - once anyone else has been in the call, being left alone ends it
///     (the other person hung up; or in a group, everyone else did). A short
///     [aloneGrace] first, so someone whose network blips and rejoins
///     doesn't end it for everyone;
///   - if nobody ever joins within [noAnswerAfter], it ends as unanswered.
///
/// Fed the number of other people in the call whenever it changes; calls
/// [onEnd] once with the reason. Separate from LiveKit so it can be tested.
class CallEndRule {
  CallEndRule({
    required this.onEnd,
    this.aloneGrace = const Duration(seconds: 3),
    this.noAnswerAfter = const Duration(seconds: 60),
  });

  final void Function(String reason) onEnd;
  final Duration aloneGrace;
  final Duration noAnswerAfter;

  static const ended = 'Call ended';
  static const noAnswer = 'No answer';

  bool _someoneJoined = false;
  bool _done = false;
  Timer? _timer;

  /// Joined the call, with [others] already in it.
  void start(int others) {
    if (others > 0) {
      _someoneJoined = true;
    } else {
      _schedule(noAnswerAfter, noAnswer);
    }
  }

  /// The number of other people in the call changed.
  void othersChanged(int others) {
    if (_done) return;
    if (others > 0) {
      _someoneJoined = true;
      _timer?.cancel();
      return;
    }
    if (_someoneJoined) _schedule(aloneGrace, ended);
  }

  /// The connection to the call is gone for good.
  void disconnected() => _finish(ended);

  void dispose() {
    _done = true;
    _timer?.cancel();
  }

  void _schedule(Duration after, String reason) {
    _timer?.cancel();
    _timer = Timer(after, () => _finish(reason));
  }

  void _finish(String reason) {
    if (_done) return;
    _done = true;
    _timer?.cancel();
    onEnd(reason);
  }
}
