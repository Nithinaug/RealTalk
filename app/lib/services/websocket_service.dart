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
  Future<void> _toPing(String url) async {
    // Just a quick check to see if the host is reachable
    try {
      final pingUrl = url.replaceFirst('/ws', '/ping').replaceFirst('ws://', 'http://').replaceFirst('wss://', 'https://');
      // We don't have http package, so we use a simple socket check if needed, 
      // but for now we'll just rely on the WebSocket's own error handling which is quite good in web_socket_channel
    } catch (_) {}
  }

  Future<void> connect(String url) async {
    _serverUrl = _toWsUrl(url);
    status = ConnectionStatus.connecting;
    errorMessage = null;
    notifyListeners();

    try {
      debugPrint('Connecting to: $_serverUrl');
      _channel = WebSocketChannel.connect(Uri.parse(_serverUrl));
      
      // Wait for the connection to be established or fail
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
      // Provide more detailed error info based on the exception type
      String detail = e.toString();
      if (detail.contains('HandshakeException')) {
        detail = 'SSL Handshake Failed. This usually means the server certificate is invalid or the protocol (WSS) is blocked.';
      } else if (detail.contains('Connection refused')) {
        detail = 'Connection Refused. Ensure the server is running and the port is correct.';
      }
      
      errorMessage = 'Failed to connect to $_serverUrl\n$detail';
      debugPrint('WebSocket Connection Error: $errorMessage');
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
    errorMessage = 'WebSocket Error: $error\n(Check if URL is correct and server is reachable)';
    notifyListeners();
  }

  void _onDone() {
    status = ConnectionStatus.disconnected;
    _joined = false;
    notifyListeners();
  }

  String _toWsUrl(String url) {
    url = url.trim();
    if (url.isEmpty) return '';

    // If it's a raw IP or localhost, try ws:// by default unless specified
    bool isLocal = url.contains('localhost') || 
                  url.contains('127.0.0.1') || 
                  url.contains('10.0.2.2');

    if (url.startsWith('https://')) {
      url = url.replaceFirst('https://', 'wss://');
    } else if (url.startsWith('http://')) {
      url = url.replaceFirst('http://', 'ws://');
    } else if (!url.startsWith('ws://') && !url.startsWith('wss://')) {
      // Default to wss:// for production UNLESS it's a local address
      url = isLocal ? 'ws://$url' : 'wss://$url';
    }

    // Ensure /ws suffix if not present
    final uri = Uri.parse(url);
    if (!uri.path.endsWith('/ws')) {
      url = url.endsWith('/') ? '${url}ws' : '$url/ws';
    }
    
    debugPrint('Connecting to WebSocket: $url');
    return url;
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
