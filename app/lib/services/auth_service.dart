import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  User? _currentUser;
  bool _isLoading = true;

  User? get currentUser => _currentUser;
  String? get currentUsername => _currentUser?.userMetadata?['username'] ?? _currentUser?.email;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser != null;

  AuthService() {
    _loadSession();
  }

  void _loadSession() {
    _currentUser = _supabase.auth.currentUser;
    _isLoading = false;
    
    _supabase.auth.onAuthStateChange.listen((data) {
      _currentUser = data.session?.user;
      notifyListeners();
    });
    
    notifyListeners();
  }

  Future<bool> signUp(String username, String password) async {
    try {
      // We use username as part of the email for simplicity or store it in metadata
      // Supabase requires an email, so we'll mock one if only username is provided
      final email = '$username@example.com'; 
      
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'username': username},
      );
      
      return response.user != null;
    } catch (e) {
      debugPrint('Signup error: $e');
      return false;
    }
  }

  Future<bool> login(String username, String password) async {
    try {
      final email = '$username@example.com';
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response.user != null;
    } catch (e) {
      debugPrint('Login error: $e');
      return false;
    }
  }

  Future<void> logout() async {
    await _supabase.auth.signOut();
  }
}
