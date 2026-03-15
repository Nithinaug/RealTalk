import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import 'chat_screen.dart';

class RoomSelectionScreen extends StatefulWidget {
  const RoomSelectionScreen({super.key});

  @override
  State<RoomSelectionScreen> createState() => _RoomSelectionScreenState();
}

class _RoomSelectionScreenState extends State<RoomSelectionScreen> {
  final _roomIDCtrl = TextEditingController();
  final _roomNameCtrl = TextEditingController();
  bool _showInput = false;
  String _actionType = ''; 
  bool _isLoading = false;
  List<Map<String, dynamic>> _joinedRooms = [];

  @override
  void initState() {
    super.initState();
    _loadJoinedRooms();
    context.read<WebSocketService>().addListener(_loadJoinedRooms);
  }

  Future<void> _loadJoinedRooms() async {
    final wsSvc = context.read<WebSocketService>();
    final rooms = await wsSvc.getJoinedRooms();
    if (mounted) {
      setState(() {
        _joinedRooms = rooms;
      });
    }
  }

  void _showRoomInput(String type) {
    setState(() {
      _showInput = true;
      _actionType = type;
      _roomIDCtrl.clear();
      _roomNameCtrl.clear();
    });
  }

  Future<void> _handleAction() async {
    final id = _roomIDCtrl.text.trim();
    final name = _roomNameCtrl.text.trim();

    if (id.isEmpty) {
      _showError('Please enter a Room ID');
      return;
    }

    final validRoomRegex = RegExp(r'^[aA-zZ0-9]+$');
    if (!validRoomRegex.hasMatch(id)) {
      _showError('Room ID can only contain letters and numbers.');
      return;
    }

    if (_actionType == 'create' && name.isEmpty) {
      _showError('Please enter a Room Name');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      
      if (_actionType == 'create') {
        final existing = await supabase.from('rooms').select('id').eq('id', id).maybeSingle();
        if (existing != null) {
          _showError('A room with this ID already exists.');
          setState(() => _isLoading = false);
          return;
        }
        _enterRoom(id, name);
      } else {
        final existing = await supabase.from('rooms').select('id, name').eq('id', id).maybeSingle();
        if (existing == null) {
          _showError('Room does not exist. Please check the ID or create a new room.');
          setState(() => _isLoading = false);
          return;
        }
        _enterRoom(id, existing['name']);
      }
    } catch (e) {
      _showError('An error occurred: $e');
      setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _enterRoom(String id, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(roomID: id, roomName: name)),
    ).then((_) => _loadJoinedRooms());
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('RealTalk', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () => auth.logout(),
            icon: const Icon(Icons.logout, color: Color(0xFF64748B)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.forum_rounded, size: 48, color: Color(0xFF22C55E)),
            ),
            const SizedBox(height: 16),
            Text(
              'RealTalk',
              style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => auth.logout(),
              child: const Text(
                'Back to Login',
                style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
            const SizedBox(height: 40),
            if (!_showInput) ...[
              if (_joinedRooms.isNotEmpty) ...[
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: _joinedRooms.length,
                  itemBuilder: (context, index) {
                    final room = _joinedRooms[index];
                    final roomId = room['id'];
                    final roomName = room['name'];
                    final creatorId = room['creator_id'];
                    final memberCount = room['member_count'] ?? 0;
                    final isCreator = creatorId == auth.currentUser?.id;

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          InkWell(
                            onTap: () => _enterRoom(roomId, roomName),
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF22C55E).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.group_rounded, color: Color(0xFF22C55E), size: 28),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    roomName,
                                    style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F172A), fontSize: 14),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$memberCount members',
                                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: isCreator 
                              ? IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                                  onPressed: () async {
                                    final confirm = await _showConfirm(context, 'Delete Room?', 'Delete this room for everyone?');
                                    if (confirm) {
                                      await context.read<WebSocketService>().deleteRoom(roomId);
                                      _loadJoinedRooms();
                                    }
                                  },
                                )
                              : IconButton(
                                  icon: const Icon(Icons.logout_rounded, color: Color(0xFF64748B), size: 18),
                                  onPressed: () async {
                                    final confirm = await _showConfirm(context, 'Exit Room?', 'Remove this room from your list?');
                                    if (confirm) {
                                      await context.read<WebSocketService>().exitRoom(roomId);
                                      _loadJoinedRooms();
                                    }
                                  },
                                ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 40),
              ],
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => _showRoomInput('create'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Text('Create New Room', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: () => _showRoomInput('join'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF22C55E),
                    side: const BorderSide(color: Color(0xFF22C55E), width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Join Room', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF475569)),
                    onPressed: () => setState(() => _showInput = false),
                  ),
                  Text(
                    _actionType == 'create' ? 'Create New Room' : 'Join Room',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (_actionType == 'create') ...[
                TextField(
                  controller: _roomNameCtrl,
                  decoration: InputDecoration(
                    hintText: 'Room Name',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _roomIDCtrl,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _handleAction(),
                decoration: InputDecoration(
                  hintText: 'Room ID',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleAction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(_actionType == 'create' ? 'Create' : 'Join', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<bool> _showConfirm(BuildContext context, String title, String content) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Confirm', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;
  }

  @override
  void dispose() {
    context.read<WebSocketService>().removeListener(_loadJoinedRooms);
    _roomIDCtrl.dispose();
    _roomNameCtrl.dispose();
    super.dispose();
  }
}
