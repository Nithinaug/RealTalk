// lib/services/websocket_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/chat_message.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  final List<ChatMessage> messages = [];
  final List<String> onlineUsers = [];

  ConnectionStatus status = ConnectionStatus.disconnected;
  String? errorMessage;

  String _serverUrl = '';
  String _username = '';
  bool _joined = false;

  bool get isJoined => _joined;
  String get username => _username;

  // ── Connect ──────────────────────────────────────────────────────────────
  Future<void> connect(String ngrokUrl) async {
    // Accept http(s) or ws(s) URLs and convert to ws(s)
    _serverUrl = _toWsUrl(ngrokUrl);
    status = ConnectionStatus.connecting;
    errorMessage = null;
    notifyListeners();

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_serverUrl));
      await _channel!.ready;

      status = ConnectionStatus.connected;
      notifyListeners();

      _subscription = _channel!.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (e) {
      status = ConnectionStatus.error;
      errorMessage = 'Could not connect: $e';
      notifyListeners();
    }
  }

  // ── Join ─────────────────────────────────────────────────────────────────
  void join(String username) {
    _username = username.trim();
    _joined = true;
    _send(ChatMessage(type: 'join', user: _username));
    notifyListeners();
  }

  // ── Send message ─────────────────────────────────────────────────────────
  void sendMessage(String text) {
    if (text.trim().isEmpty || !_joined) return;
    final msg = ChatMessage(type: 'message', user: _username, text: text.trim());
    _send(msg);
  }

  // ── Disconnect ───────────────────────────────────────────────────────────
  void disconnect() {
    _subscription?.cancel();
    _channel?.sink.close();
    _joined = false;
    status = ConnectionStatus.disconnected;
    messages.clear();
    onlineUsers.clear();
    notifyListeners();
  }

  // ── Internals ─────────────────────────────────────────────────────────────
  void _send(ChatMessage msg) {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode(msg.toJson()));
  }

  void _onData(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final msg = ChatMessage.fromJson(json);

      if (msg.type == 'users') {
        onlineUsers
          ..clear()
          ..addAll(msg.users ?? []);
      } else if (msg.type == 'message') {
        messages.add(msg);
      }
      notifyListeners();
    } catch (_) {}
  }

  void _onError(Object error) {
    status = ConnectionStatus.error;
    errorMessage = error.toString();
    notifyListeners();
  }

  void _onDone() {
    status = ConnectionStatus.disconnected;
    _joined = false;
    notifyListeners();
  }

  String _toWsUrl(String url) {
    url = url.trim().replaceAll(RegExp(r'/$'), '');
    if (url.startsWith('https://')) {
      return url.replaceFirst('https://', 'wss://') + '/ws';
    } else if (url.startsWith('http://')) {
      return url.replaceFirst('http://', 'ws://') + '/ws';
    } else if (!url.startsWith('ws')) {
      return 'ws://$url/ws';
    }
    return url.endsWith('/ws') ? url : '$url/ws';
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
