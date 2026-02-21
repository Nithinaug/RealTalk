// lib/screens/chat_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/online_users_sheet.dart';
import 'login_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

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
    // Auto-connect when screen is initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoConnect();
    });
  }

  Future<void> _autoConnect() async {
    final auth = context.read<AuthService>();
    final ws = context.read<WebSocketService>();
    
    if (auth.currentUsername != null && ws.status != ConnectionStatus.connected) {
      // 1. Production Render URL
      // 2. Local Emulator (10.0.2.2)
      // 3. Localhost (127.0.0.1)
      final List<String> urlsToTry = [
        'wss://real-time-chatroom-6f6f.onrender.com/ws', 
        'ws://10.0.2.2:8080/ws',                     
        'ws://localhost:8080/ws',                  
      ];

      for (final url in urlsToTry) {
        debugPrint('Connecting to: $url');
        await ws.connect(url);
        if (ws.status == ConnectionStatus.connected) {
          ws.join(auth.currentUsername!);
          return;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ws.errorMessage ?? 'Connection failed. Check your internet or server.'),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 5),
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
    // This is called when we want to MANUALLY disconnect and go to login
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

    // Auto-scroll on new messages
    if (svc.messages.isNotEmpty) _scrollToBottom();

    // Handle disconnection or errors
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
    } else if (svc.status == ConnectionStatus.connecting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connecting to server...'),
              backgroundColor: Color(0xFF475569),
              duration: Duration(seconds: 2),
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
            // ── Header ──────────────────────────────────────
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
                        const Text(
                          'Chat Room',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'You: ${svc.username}',
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF475569)),
                        ),
                      ],
                    ),
                  ),

                  // Online badge
                  GestureDetector(
                    onTap: () => setState(() => _usersVisible = !_usersVisible),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
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
                            '${svc.onlineUsers.length} online',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Leave button
                  IconButton(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout_rounded),
                    color: const Color(0xFF475569),
                    tooltip: 'Logout and exit',
                  ),
                ],
              ),
            ),

            // ── Online users slide-down panel ────────────────
            if (_usersVisible)
              OnlineUsersSheet(
                users: svc.onlineUsers,
                currentUser: svc.username,
                onClose: () => setState(() => _usersVisible = false),
              ),

            // ── Messages list ────────────────────────────────
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
                            'No messages yet.\nSay hello!',
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

            // ── Input bar ────────────────────────────────────
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
