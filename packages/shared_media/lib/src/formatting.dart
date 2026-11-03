/// "0:07", "1:30" — how long a video is.
String formatVideoDuration(int milliseconds) {
  final seconds = (milliseconds / 1000).round();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
