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
  String _currentRoomID = '';
  String _currentRoomName = '';
  bool _joined = false;

  bool get isJoined => _joined;
  String get username => _username;
  String get currentRoomID => _currentRoomID;

  Future<void> _fetchHistory() async {
    if (_currentRoomID.isEmpty) return;
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final clearData = await _supabase
          .from('user_room_clears')
          .select('cleared_at')
          .eq('user_id', user.id)
          .eq('room_id', _currentRoomID)
          .maybeSingle();
      
      final clearedAt = clearData?['cleared_at'] ?? '1970-01-01T00:00:00Z';

      final deletedData = await _supabase
          .from('user_deleted_messages')
          .select('message_id')
          .eq('user_id', user.id);
      
      final deletedIDs = (deletedData as List).map((d) => d['message_id'].toString()).toList();

      final data = await _supabase
          .from('messages')
          .select()
          .eq('room_id', _currentRoomID)
          .gt('created_at', clearedAt)
          .order('created_at', ascending: true)
          .limit(100);
      
      messages.clear();
      for (var row in data) {
        if (!deletedIDs.contains(row['id'].toString())) {
          messages.add(ChatMessage(
            id: row['id'].toString(),
            type: 'message',
            user: row['username'],
            text: row['text'],
            roomID: row['room_id'],
            timestamp: DateTime.parse(row['created_at']).toLocal(),
          ));
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching history: $e');
    }
  }

  void _setupSupabaseRealtime() {
    if (_currentRoomID.isEmpty) return;
    _supabaseChannel?.unsubscribe();
    
    _supabaseChannel = _supabase.channel('room:$_currentRoomID')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'room_id',
          value: _currentRoomID,
        ),
        callback: (payload) {
          final newMessage = ChatMessage(
            id: payload.newRecord['id'].toString(),
            type: 'message',
            user: payload.newRecord['username'],
            text: payload.newRecord['text'],
            roomID: payload.newRecord['room_id'],
            timestamp: DateTime.parse(payload.newRecord['created_at']).toLocal(),
          );
          
          if (!messages.any((m) => m.id == newMessage.id)) {
             messages.add(newMessage);
             notifyListeners();
          }
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'user_deleted_messages',
        callback: (payload) {
          final msgId = payload.newRecord['message_id'].toString();
          messages.removeWhere((m) => m.id == msgId);
          notifyListeners();
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'user_room_clears',
        callback: (payload) {
          final user = _supabase.auth.currentUser;
          if (user != null && 
              payload.newRecord['room_id'] == _currentRoomID && 
              payload.newRecord['user_id'] == user.id) {
            messages.clear();
            notifyListeners();
          }
        },
      ).subscribe();
  }

  Future<void> connect(String url, String roomID) async {
    _serverUrl = _toWsUrl(url);
    _currentRoomID = roomID;
    status = ConnectionStatus.connecting;
    errorMessage = null;
    notifyListeners();

    await _fetchHistory();
    _setupSupabaseRealtime();

    try {
      _channel?.sink.close();
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

      _subscription?.cancel();
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

  Future<void> join(String username, String roomID, String roomName) async {
    _username = username.trim();
    _currentRoomID = roomID;
    _currentRoomName = roomName;
    _joined = true;
    
    final user = _supabase.auth.currentUser;
    if (user != null) {
      final roomData = await _supabase.from('rooms').select().eq('id', roomID).maybeSingle();
      if (roomData == null) {
        await _supabase.from('rooms').insert({'id': roomID, 'name': roomName, 'creator_id': user.id});
      }
      await _supabase.from('user_rooms').upsert({'user_id': user.id, 'room_id': roomID});
    }

    _send(ChatMessage(type: 'join', user: _username, roomID: _currentRoomID));
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getJoinedRooms() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final data = await _supabase
          .from('user_rooms')
          .select('rooms(id, name, creator_id)')
          .eq('user_id', user.id);
      
      return (data as List).map((item) {
        final room = item['rooms'];
        if (room == null) return null;
        return room as Map<String, dynamic>;
      }).whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      debugPrint('Error fetching joined rooms: $e');
      return [];
    }
  }

  Future<void> deleteRoom(String id) async {
    try {
      await _supabase.from('rooms').delete().eq('id', id);
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting room: $e');
    }
  }

  Future<void> exitRoom(String id) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      await _supabase.from('user_rooms').delete().eq('user_id', user.id).eq('room_id', id);
      notifyListeners();
    } catch (e) {
      debugPrint('Error exiting room: $e');
    }
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _currentRoomID.isEmpty) return;
    
    if (!_joined && _username.isNotEmpty) {
       await connect(_serverUrl, _currentRoomID);
       if (status == ConnectionStatus.connected) join(_username, _currentRoomID, _currentRoomName);
    }

    try {
      final response = await _supabase.from('messages').insert({
        'username': _username,
        'text': text.trim(),
        'room_id': _currentRoomID,
      }).select().single();

      if (_joined) {
        final msg = ChatMessage(
          id: response['id'],
          type: 'message', 
          user: _username, 
          text: text.trim(), 
          roomID: _currentRoomID
        );
        _send(msg);
        if (!messages.any((m) => m.id == msg.id)) {
          messages.add(msg);
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error saving to Supabase: $e');
    }
  }

  Future<void> deleteMessageForMe(String msgId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase.from('user_deleted_messages').insert({
        'user_id': user.id,
        'message_id': msgId,
      });
      messages.removeWhere((m) => m.id == msgId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting message: $e');
    }
  }

  Future<void> clearRoomForMe() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null || _currentRoomID.isEmpty) return;

      await _supabase.from('user_room_clears').upsert({
        'user_id': user.id,
        'room_id': _currentRoomID,
        'cleared_at': DateTime.now().toIso8601String(),
      });
      messages.clear();
      notifyListeners();
    } catch (e) {
      debugPrint('Error clearing room: $e');
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
      final map = msg.toJson();
      _channel!.sink.add(jsonEncode(map));
    } catch (e) {
      debugPrint('Failed to send WS message: $e');
    }
  }

  void _onData(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      if (json.containsKey('room_id')) {
        json['roomID'] = json.remove('room_id');
      }
      final msg = ChatMessage.fromJson(json);

      if (msg.type == 'users') {
        if (msg.roomID == _currentRoomID) {
          onlineUsers
            ..clear()
            ..addAll(msg.users ?? []);
          notifyListeners();
        }
      } else if (msg.type == 'message') {
        if (msg.roomID == _currentRoomID && !messages.any((m) => m.id == msg.id)) {
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
    debugPrint('WebSocket closed. Retrying in 3 seconds...');
    Future.delayed(const Duration(seconds: 3), () {
      if (_username.isNotEmpty && status == ConnectionStatus.disconnected) {
        connect(_serverUrl, _currentRoomID).then((_) {
          if (status == ConnectionStatus.connected) {
            join(_username, _currentRoomID, _currentRoomName);
          }
        });
      }
    });
  }
}
