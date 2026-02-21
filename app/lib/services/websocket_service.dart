import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_message.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

class WebSocketService extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  RealtimeChannel? _supabaseChannel;

  final List<ChatMessage> messages = [];
  final List<String> onlineUsers = [];

  ConnectionStatus status = ConnectionStatus.disconnected;
  String? errorMessage;

  String _serverUrl = '';
  String _username = '';
  bool _joined = false;

  bool get isJoined => _joined;
  String get username => _username;

  // -- Supabase Persistence --
  Future<void> _fetchHistory() async {
    try {
      final data = await _supabase
          .from('messages')
          .select()
          .order('created_at', ascending: true)
          .limit(100);
      
      messages.clear();
      for (var row in data) {
        messages.add(ChatMessage(
          type: 'message',
          user: row['username'],
          text: row['text'],
          timestamp: DateTime.parse(row['created_at']),
        ));
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching history: $e');
    }
  }

  void _setupSupabaseRealtime() {
    _supabaseChannel = _supabase.channel('public:messages')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (payload) {
          final newMessage = ChatMessage(
            type: 'message',
            user: payload.newRecord['username'],
            text: payload.newRecord['text'],
            timestamp: DateTime.parse(payload.newRecord['created_at']),
          );
          
          // Only add if not already in list (to avoid double adding from broadcast)
          if (!messages.any((m) => m.text == newMessage.text && m.user == newMessage.user && (m.timestamp.difference(newMessage.timestamp).inSeconds.abs() < 2))) {
             messages.add(newMessage);
             notifyListeners();
          }
        },
      ).subscribe();
  }

  // ── Connect ──────────────────────────────────────────────────────────────
  Future<void> connect(String url) async {
    _serverUrl = _toWsUrl(url);
    status = ConnectionStatus.connecting;
    errorMessage = null;
    notifyListeners();

    // Fetch history from Supabase
    await _fetchHistory();
    _setupSupabaseRealtime();

    try {
      debugPrint('Connecting to: $_serverUrl');
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
      // We still consider ourselves "connected" if Supabase is working? 
      // Actually, let's keep the WebSocket as secondary/status only.
      status = ConnectionStatus.error;
      errorMessage = 'WebSocket Error: $e. However, Supabase messages may still work.';
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
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || !_joined) return;
    
    // 1. Save to Supabase
    try {
      await _supabase.from('messages').insert({
        'username': _username,
        'text': text.trim(),
      });
    } catch (e) {
      debugPrint('Error saving to Supabase: $e');
    }

    // 2. Broadcast via WebSocket (for instant feedback in current Go setup)
    final msg = ChatMessage(type: 'message', user: _username, text: text.trim());
    _send(msg);
  }

  // ── Disconnect ───────────────────────────────────────────────────────────
  void disconnect() {
    _subscription?.cancel();
    _channel?.sink.close();
    _supabaseChannel?.unsubscribe();
    _joined = false;
    status = ConnectionStatus.disconnected;
    // messages.clear(); // Keep messages ? User said they want persistence.
    onlineUsers.clear();
    notifyListeners();
  }

  // ── Internals ─────────────────────────────────────────────────────────────
  void _send(ChatMessage msg) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(msg.toJson()));
    } catch (_) {}
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
        // If we get it from WebSocket, only add if not from Supabase?
        // Actually, let's let Supabase handle the persistent truth.
        // But for live feel, we can add it here if it's not already there.
        if (!messages.any((m) => m.text == msg.text && m.user == msg.user)) {
           messages.add(msg);
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  void _onError(Object error) {
    debugPrint('WebSocket Error: $error');
  }

  void _onDone() {
    status = ConnectionStatus.disconnected;
    _joined = false;
    notifyListeners();
  }

  String _toWsUrl(String url) {
    url = url.trim();
    if (url.isEmpty) return '';
    bool isLocal = url.contains('localhost') || url.contains('127.0.0.1') || url.contains('10.0.2.2');
    if (url.startsWith('https://')) {
      url = url.replaceFirst('https://', 'wss://');
    } else if (url.startsWith('http://')) {
      url = url.replaceFirst('http://', 'ws://');
    } else if (!url.startsWith('ws://') && !url.startsWith('wss://')) {
      url = isLocal ? 'ws://$url' : 'wss://$url';
    }
    final uri = Uri.parse(url);
    if (!uri.path.endsWith('/ws')) {
      url = url.endsWith('/') ? '${url}ws' : '$url/ws';
    }
    return url;
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
