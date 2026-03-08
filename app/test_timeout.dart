import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() async {
  print('Trying 10.0.2.2...');
  try {
    final channel = WebSocketChannel.connect(Uri.parse('ws://10.0.2.2:8080/ws'));
    await channel.ready.timeout(Duration(seconds: 3));
    print('Connected');
  } catch (e) {
    print('Error: \$e');
  }
}
