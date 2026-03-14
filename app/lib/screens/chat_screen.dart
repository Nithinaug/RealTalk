import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/online_users_sheet.dart';
import '../models/chat_message.dart';
import 'login_screen.dart';
import 'room_selection_screen.dart';

class ChatScreen extends StatefulWidget {
  final String roomID;
  final String roomName;
  const ChatScreen({super.key, required this.roomID, required this.roomName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _usersVisible = false;
  List<Map<String, dynamic>> _myRooms = [];
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _loadRooms();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoConnect();
    });
  }

  Future<void> _loadRooms() async {
    final svc = context.read<WebSocketService>();
    final rooms = await svc.getJoinedRooms();
    if (mounted) setState(() => _myRooms = rooms);
  }

  Future<void> _autoConnect() async {
    final auth = context.read<AuthService>();
    final ws = context.read<WebSocketService>();

    if (auth.currentUsername == null) return;
    if (ws.status == ConnectionStatus.connected && ws.currentRoomID == widget.roomID) return;

    final appUrl = dotenv.maybeGet('APP_URL') ?? 'https://realtalk-f233.onrender.com';
    final urls = [appUrl, 'ws://10.0.2.2:8080/ws'];

    for (final url in urls) {
      for (int attempt = 0; attempt < 3; attempt++) {
        await ws.connect(url, widget.roomID);
        if (ws.status == ConnectionStatus.connected) {
          await ws.join(auth.currentUsername!, widget.roomID, widget.roomName);
          _loadRooms();
          return;
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not connect to server'),
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

  void _logout() async {
    context.read<WebSocketService>().disconnect();
    context.read<AuthService>().logout();
    Navigator.pushAndRemoveUntil(
      context, 
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<bool> _showConfirm(String title, String content) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_sweep_rounded, color: Color(0xFF475569)),
              title: const Text('Clear Chat History for Me'),
              onTap: () {
                Navigator.pop(ctx);
                showDialog(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    title: const Text('Clear History?'),
                    content: const Text('Clear room history for you? This will sync across your devices.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          context.read<WebSocketService>().clearRoomForMe();
                          Navigator.pop(dialogCtx);
                        },
                        child: const Text('Clear', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.meeting_room_rounded, color: Color(0xFF475569)),
              title: const Text('Leave Room'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
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
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: Drawer(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.only(top: 60, bottom: 24, left: 20, right: 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              width: double.infinity,
              child: Text(
                'My Rooms',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _myRooms.length,
                itemBuilder: (ctx, i) {
                  final room = _myRooms[i];
                  final roomId = room['id'];
                  final roomName = room['name'];
                  final creatorId = room['creator_id'];
                  final isActive = roomId == widget.roomID;
                  final auth = context.read<AuthService>();
                  final isCreator = creatorId == auth.currentUser?.id;

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFFF0FDF4) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: Icon(
                        Icons.forum_rounded,
                        color: isActive ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
                        size: 22,
                      ),
                      title: Text(
                        roomName,
                        style: GoogleFonts.inter(
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                          color: isActive ? const Color(0xFF166534) : const Color(0xFF334155),
                        ),
                      ),
                      trailing: isCreator 
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                            onPressed: () async {
                              final confirm = await _showConfirm('Delete Room?', 'Delete this room for everyone?');
                              if (confirm) {
                                await svc.deleteRoom(roomId);
                                _loadRooms();
                                if (isActive) Navigator.pop(context);
                              }
                            },
                          )
                        : null,
                      onTap: () {
                        if (!isActive) {
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(roomID: roomId, roomName: roomName)));
                        } else {
                          Navigator.pop(context);
                        }
                      },
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const RoomSelectionScreen()));
                },
                icon: const Icon(Icons.add_circle_rounded, size: 20),
                label: Text(
                  'Join / Create Room',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF22C55E),
                  elevation: 0,
                  side: const BorderSide(color: Color(0xFF22C55E), width: 2),
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              leading: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444)),
              title: Text(
                'Logout',
                style: GoogleFonts.inter(
                  color: const Color(0xFFEF4444),
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: _logout,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    spreadRadius: 0,
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    icon: const Icon(Icons.menu_rounded,
                        color: Color(0xFF0F172A), size: 24),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.roomName,
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        GestureDetector(
                          onTap: () => setState(() => _usersVisible = !_usersVisible),
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
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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
                    icon: const Icon(Icons.delete_sweep_rounded, size: 24),
                    color: const Color(0xFF64748B),
                    tooltip: 'Clear chat for me',
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
              child: ListView.builder(
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
