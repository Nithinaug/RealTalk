import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/websocket_service.dart';
import 'services/auth_service.dart';
import 'screens/room_selection_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await dotenv.load(fileName: ".env");
  await Supabase.initialize(
    url: dotenv.get('SUPABASE_URL'),
    anonKey: dotenv.get('SUPABASE_ANON_KEY'),
  );

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => WebSocketService()),
      ],
      child: MaterialApp(
        title: 'RealTalk',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF22C55E),
            brightness: Brightness.light,
          ),
          fontFamily: 'Arial',
          useMaterial3: true,
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  String? _lastRoom;
  bool _checkedPrefs = false;

  @override
  void initState() {
    super.initState();
    _checkPrefs();
  }

  Future<void> _checkPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    // Assuming auth state is accessible via context.read when we get to build
    // but SharedPreferences async fetch happens first.
    setState(() => _checkedPrefs = true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    if (auth.isLoading || !_checkedPrefs) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!auth.isAuthenticated) {
      return const LoginScreen();
    }

    final username = auth.currentUsername ?? '';
    if (username.isNotEmpty) {
      SharedPreferences.getInstance().then((prefs) {
        final roomsStr = prefs.getString('rooms_$username') ?? '[]';
        List<String> rooms = List<String>.from(json.decode(roomsStr));
        if (rooms.isNotEmpty && _lastRoom != rooms.first && mounted) {
          setState(() => _lastRoom = rooms.first);
        }
      });
    }

    if (_lastRoom != null) {
      return ChatScreen(roomID: _lastRoom!);
    }

    return const RoomSelectionScreen();
  }
}
