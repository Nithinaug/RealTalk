// lib/services/auth_service.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AuthService extends ChangeNotifier {
  static const String _keyUsername = 'logged_in_username';
  static const String _keyUsers = 'registered_users';

  String? _currentUser;
  bool _isLoading = true;

  String? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser != null;

  AuthService() {
    _loadSession();
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUser = prefs.getString(_keyUsername);
    _isLoading = false;
    notifyListeners();
  }

  Future<Map<String, String>> _getUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final String? usersJson = prefs.getString(_keyUsers);
    if (usersJson == null) return {};
    return Map<String, String>.from(json.decode(usersJson));
  }

  Future<bool> signUp(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final users = await _getUsers();

    if (users.containsKey(username)) {
      return false; // User already exists
    }

    users[username] = password;
    await prefs.setString(_keyUsers, json.encode(users));
    return true;
  }

  Future<bool> login(String username, String password) async {
    final users = await _getUsers();

    if (users.containsKey(username) && users[username] == password) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUsername, username);
      _currentUser = username;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsername);
    _currentUser = null;
    notifyListeners();
  }
}
