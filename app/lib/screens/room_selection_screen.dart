import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('RealTalk', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFA6D6B8),
        actions: [
          IconButton(
            onPressed: () => auth.logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.forum_rounded, size: 80, color: Color(0xFF22C55E)),
              const SizedBox(height: 32),
              Text(
                'Welcome, ${auth.currentUsername}!',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Create a new room or join an existing one to start chatting.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF64748B), fontSize: 16),
              ),
              const SizedBox(height: 48),
              if (!_showInput) ...[
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () => _showRoomInput('create'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22C55E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Create New Room', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 24),
                const Row(
                  children: [
                    Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('OR', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                    ),
                    Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () => _showRoomInput('join'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22C55E),
                      foregroundColor: Colors.white,
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
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF3E4D61)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_actionType == 'create') ...[
                  TextField(
                    controller: _roomNameCtrl,
                    decoration: InputDecoration(
                      hintText: 'Room Name',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      border: OutlineInputBorder(
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
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleAction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22C55E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
      ),
    );
  }

  @override
  void dispose() {
    _roomIDCtrl.dispose();
    _roomNameCtrl.dispose();
    super.dispose();
  }
}
