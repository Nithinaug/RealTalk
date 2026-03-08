import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

String toWsUrl(String url) {
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

void main() async {
  final urlsToTry = [
    'wss://realtalk-f233.onrender.com/ws', 
    'ws://10.0.2.2:8080/ws',                     
    'ws://localhost:8080/ws',                  
  ];
  for (final rawUrl in urlsToTry) {
    final finalUrl = toWsUrl(rawUrl);
    print('Trying finalUrl: \$finalUrl');
    try {
      final channel = WebSocketChannel.connect(Uri.parse(finalUrl));
      await channel.ready;
      print('Connected to \$finalUrl');
      channel.sink.add(jsonEncode({'type': 'join', 'user': 'dart_loop_test'}));
      channel.sink.add(jsonEncode({'type': 'message', 'user': 'dart_loop_test', 'text': 'hello from loop dart'}));
      await Future.delayed(Duration(seconds: 1));
      channel.sink.close();
      return; 
    } catch (e) {
      print('Failed \$finalUrl: \$e');
    }
  }
}
