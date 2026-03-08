import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

void main() async {
  print('Connecting...');
  try {
    final channel = WebSocketChannel.connect(Uri.parse('wss://realtalk-f233.onrender.com/ws'));
    await channel.ready;
    print('Connected');
    channel.sink.add(jsonEncode({'type': 'join', 'user': 'dart_test'}));
    channel.sink.add(jsonEncode({'type': 'message', 'user': 'dart_test', 'text': 'hello from dart'}));
    
    await Future.delayed(Duration(seconds: 2));
    channel.sink.close();
    print('Done');
  } catch (e) {
    print('Error: $e');
  }
}
