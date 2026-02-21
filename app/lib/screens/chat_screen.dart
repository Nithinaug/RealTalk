// lib/screens/chat_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/online_users_sheet.dart';
import 'connect_screen.dart';
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
    // Just goes back to connect screen, doesn't logout
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ConnectScreen()),
    );
  }

  void _logout() async {
    context.read<WebSocketService>().disconnect();
    await context.read<AuthService>().logout();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<WebSocketService>();

    // Auto-scroll on new messages
    if (svc.messages.isNotEmpty) _scrollToBottom();

    // Handle disconnection
    if (svc.status == ConnectionStatus.disconnected ||
        svc.status == ConnectionStatus.error) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(svc.errorMessage ?? 'Disconnected from server'),
              backgroundColor: Colors.red.shade600,
              action: SnackBarAction(
                label: 'Reconnect',
                textColor: Colors.white,
                onPressed: _disconnect,
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
