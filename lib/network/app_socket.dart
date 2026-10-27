import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_client.dart';

/// One persistent connection carrying every realtime event this app cares
/// about — feed_updated (from FeedSocket.kt's original job), plus
/// message_created and read_receipt_updated (chat's live nudges, see
/// chatConsumer.ts). It's one server-side WebSocket per user regardless of
/// how many kinds of events flow over it, so this is one client-side
/// connection too, not a separate socket per feature the way a first pass
/// might tempt you to build. Exposes decoded JSON events as a broadcast
/// stream; each screen's view model filters for the "type" it cares about.
class AppSocket {
  final int userId;
  WebSocketChannel? _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  AppSocket(this.userId);

  Stream<Map<String, dynamic>> get events => _controller.stream;

  void connect() {
    // Derived from ApiClient.baseUrl instead of a second hardcoded host —
    // the whole reason "can't log in on a real phone" happened was 10.0.2.2
    // living in two separate places and only one getting updated. The
    // ws/wss choice has to track http/https: the VM's backend sits behind
    // Caddy's TLS termination, so a plain ws:// there fails outright.
    final httpUri = Uri.parse('${ApiClient.baseUrl}/ws?userId=$userId');
    final uri = httpUri.replace(scheme: httpUri.scheme == 'https' ? 'wss' : 'ws');
    _channel = WebSocketChannel.connect(uri);
    _channel!.stream.listen(
      (raw) {
        try {
          _controller.add(jsonDecode(raw as String) as Map<String, dynamic>);
        } catch (_) {
          // Not JSON — ignore rather than crash the whole connection.
        }
      },
      onError: (_) {},
      onDone: () {},
    );
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
