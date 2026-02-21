// lib/screens/connect_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../services/auth_service.dart';
import 'chat_screen.dart';

const String kServerUrl = 'wss://real-time-chat-6f6f.onrender.com/ws';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _nameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthService>();
    if (auth.currentUser != null) {
      _nameCtrl.text = auth.currentUser!;
    }
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    final svc = context.read<WebSocketService>();
    await svc.connect(kServerUrl);
    if (!mounted) return;
    if (svc.status == ConnectionStatus.connected) {
      // Use the pre-filled name or the one edited by user (though it's pre-filled)
      svc.join(_nameCtrl.text.trim());
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ChatScreen()));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(svc.errorMessage ?? 'Connection failed'), backgroundColor: Colors.red.shade600));
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<WebSocketService>();
    final isConnecting = svc.status == ConnectionStatus.connecting;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFFA6D6B8),
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: const Text('Chat Room', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.chat_bubble_rounded, size: 72, color: Color(0xFF22C55E)),
                        const SizedBox(height: 24),
                        const Text('Welcome!', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                        const SizedBox(height: 8),
                        const Text('Enter your name to join the chat.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Color(0xFF64748B))),
                        const SizedBox(height: 32),
                        const Text('Your Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _nameCtrl,
                          textCapitalization: TextCapitalization.words,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: 'Enter your display name',
                            hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF22C55E), width: 2)),
                            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.red)),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Please enter your name';
                            if (v.trim().length < 2) return 'Name must be at least 2 characters';
                            return null;
                          },
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: isConnecting ? null : _connect,
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
                            child: isConnecting ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Join Chat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }
}
