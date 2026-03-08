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
          timestamp: DateTime.parse(row['created_at']).toLocal(),
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
            timestamp: DateTime.parse(payload.newRecord['created_at']).toLocal(),
          );
          
          if (!messages.any((m) => m.text == newMessage.text && m.user == newMessage.user && (m.timestamp.difference(newMessage.timestamp).inSeconds.abs() < 2))) {
             messages.add(newMessage);
             notifyListeners();
          }
        },
      ).subscribe();
  }

  Future<void> connect(String url) async {
    _serverUrl = _toWsUrl(url);
    status = ConnectionStatus.connecting;
    errorMessage = null;
    notifyListeners();

    await _fetchHistory();
    _setupSupabaseRealtime();

    try {
      debugPrint('Connecting to: $_serverUrl');
      // Set a generic pingInterval on WebSocketChannel 
      // Unfortunately package:web_socket_channel's `connect` 
      // does not support `pingInterval` directly unless you use an IOWebSocketChannel.
      _channel = WebSocketChannel.connect(Uri.parse(_serverUrl));
      await _channel!.ready;

      status = ConnectionStatus.connected;
      notifyListeners();

      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
        if (_channel != null && status == ConnectionStatus.connected) {
           _send(ChatMessage(type: 'ping'));
        }
      });

      _subscription = _channel!.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (e) {
      status = ConnectionStatus.error;
      errorMessage = 'WebSocket Error: $e.';
      notifyListeners();
    }
  }

  void join(String username) {
    _username = username.trim();
    _joined = true;
    _send(ChatMessage(type: 'join', user: _username));
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    
    // If not joined (e.g. connection dropped), try to reconnect but don't block saving to DB
    if (!_joined && _username.isNotEmpty) {
       debugPrint('Waiting to reconnect before sending: $_serverUrl');
       try {
         await connect(_serverUrl);
         if (status == ConnectionStatus.connected) {
           join(_username);
         }
       } catch (e) {
         debugPrint('Reconnect failed during send: $e');
       }
    }

    try {
      await _supabase.from('messages').insert({
        'username': _username,
        'text': text.trim(),
      });
    } catch (e) {
      debugPrint('Error saving to Supabase: $e');
    }

    if (_joined) {
      final msg = ChatMessage(type: 'message', user: _username, text: text.trim());
      _send(msg);
    }
  }

  void clearMessages() {
    messages.clear();
    notifyListeners();
  }

  Timer? _pingTimer;

  void disconnect() {
    _subscription?.cancel();
    _channel?.sink.close();
    _supabaseChannel?.unsubscribe();
    _pingTimer?.cancel();
    _pingTimer = null;
    _joined = false;
    status = ConnectionStatus.disconnected;
    onlineUsers.clear();
    notifyListeners();
  }

  void _send(ChatMessage msg) {
    if (_channel == null) return;
    try {
      final jsonStr = jsonEncode(msg.toJson());
      _channel!.sink.add(jsonStr);
      debugPrint('Sent WS message: $jsonStr');
    } catch (e) {
      debugPrint('Failed to send WS message: $e');
    }
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

  void _onDone() {
    status = ConnectionStatus.disconnected;
    _joined = false;
    notifyListeners();
    debugPrint('WebSocket closed. Assuming dropped connection, retrying in 3 seconds...');
    Future.delayed(const Duration(seconds: 3), () {
      if (_username.isNotEmpty && status == ConnectionStatus.disconnected) {
        connect(_serverUrl).then((_) {
          if (status == ConnectionStatus.connected) {
            join(_username);
          }
        });
      }
    });
  }
}
