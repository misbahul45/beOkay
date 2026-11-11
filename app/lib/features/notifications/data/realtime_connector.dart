import 'dart:async';
import 'dart:convert';
import 'dart:io';

abstract interface class RealtimeConnection {
  Stream<Map<String, dynamic>> get events;
  void send(Map<String, dynamic> message);
  Future<void> close();
}

abstract interface class RealtimeConnector {
  Future<RealtimeConnection> connect(Uri uri, String token);
}

class IoRealtimeConnector implements RealtimeConnector {
  @override
  Future<RealtimeConnection> connect(Uri uri, String token) async {
    final socket = await WebSocket.connect(
      uri.toString(),
      headers: {'authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 10));
    return _IoConnection(socket);
  }
}

class _IoConnection implements RealtimeConnection {
  _IoConnection(this.socket);
  final WebSocket socket;

  @override
  Stream<Map<String, dynamic>> get events => socket
      .where((m) => m is String)
      .map((m) {
        try {
          final v = jsonDecode(m as String);
          return v is Map<String, dynamic> ? v : <String, dynamic>{};
        } catch (_) {
          return <String, dynamic>{};
        }
      })
      .where((m) => m.isNotEmpty);

  @override
  void send(Map<String, dynamic> message) => socket.add(jsonEncode(message));

  @override
  Future<void> close() => socket.close();
}

class SilentRealtimeConnector implements RealtimeConnector {
  @override
  Future<RealtimeConnection> connect(Uri uri, String token) =>
      Completer<RealtimeConnection>().future;
}
