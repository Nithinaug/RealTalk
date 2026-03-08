import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/online_users_sheet.dart';
import 'login_screen.dart';

class ChatScreen extends StatefulWidget {
  final String roomID;
  const ChatScreen({super.key, required this.roomID});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _usersVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoConnect();
    });
  }

  Future<void> _autoConnect() async {
    final auth = context.read<AuthService>();
    final ws = context.read<WebSocketService>();
    
    if (auth.currentUsername != null && (ws.status != ConnectionStatus.connected || ws.currentRoomID != widget.roomID)) {
      final appUrl = dotenv.maybeGet('APP_URL') ?? 'https://realtalk-f233.onrender.com';
      final List<String> urlsToTry = [
        appUrl,
        'ws://10.0.2.2:8080/ws',
        'ws://localhost:8080/ws',
      ];

      String lastError = 'Connection failed';
      for (final url in urlsToTry) {
        debugPrint('Attempting connection to: $url in room ${widget.roomID}');
        await ws.connect(url, widget.roomID);
        if (ws.status == ConnectionStatus.connected) {
          ws.join(auth.currentUsername!, widget.roomID);
          return;
        }
        lastError = ws.errorMessage ?? 'Failed to connect to $url';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lastError),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _autoConnect,
            ),
          ),
        );
      }
    }
  }

  void _sendMessage() {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    context.read<WebSocketService>().sendMessage(text);
    _msgCtrl.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _disconnect() {
    context.read<WebSocketService>().disconnect();
    context.read<AuthService>().logout();
    Navigator.pushAndRemoveUntil(
      context, 
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _logout() async {
    _disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<WebSocketService>();

    if (svc.messages.isNotEmpty) _scrollToBottom();

    if (svc.status == ConnectionStatus.error) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(svc.errorMessage ?? 'Connection Failed'),
              backgroundColor: Colors.red.shade600,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 10),
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: _autoConnect,
              ),
            ),
          );
        }
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: const Color(0xFFA6D6B8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Room: ${widget.roomID}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'User: ${svc.username}',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF475569)),
                        ),
                      ],
                    ),
                  ),

                  GestureDetector(
                    onTap: () => setState(() => _usersVisible = !_usersVisible),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF22C55E),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${svc.onlineUsers.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),

                  IconButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Clear History?'),
                          content: const Text('Clear room history for you? This will sync across your devices.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () {
                                svc.clearRoomForMe();
                                Navigator.pop(ctx);
                              },
                              child: const Text('Clear', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.delete_sweep_rounded),
                    color: const Color(0xFF475569),
                    tooltip: 'Clear room for me',
                  ),

                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.meeting_room_rounded),
                    color: const Color(0xFF475569),
                    tooltip: 'Leave room',
                  ),
                ],
              ),
            ),

            if (_usersVisible)
              OnlineUsersSheet(
                users: svc.onlineUsers,
                currentUser: svc.username,
                onClose: () => setState(() => _usersVisible = false),
              ),

            Expanded(
              child: svc.messages.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.forum_outlined,
                              size: 56, color: Color(0xFFCBD5E1)),
                          SizedBox(height: 12),
                          Text(
                            'No messages yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Color(0xFF94A3B8), fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: svc.messages.length,
                      itemBuilder: (_, i) {
                        final msg = svc.messages[i];
                        final isMe = msg.user == svc.username;
                        return MessageBubble(
                          message: msg,
                          isMe: isMe,
                        );
                      },
                    ),
            ),

            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Type a message…',
                        hintStyle:
                            const TextStyle(color: Color(0xFF94A3B8)),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Color(0xFF22C55E),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }
}
