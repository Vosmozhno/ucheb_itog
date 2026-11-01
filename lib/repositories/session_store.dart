import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class SessionStore {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> value);
  Future<void> clear();
  Future<String?> readDemoRole();
}

class PreferencesSessionStore implements SessionStore {
  PreferencesSessionStore(this.preferences);
  final SharedPreferences preferences;
  static const sessionKey = 'pohod.session';
  static const demoRoleKey = 'pohod.ui_role';
  @override
  Future<Map<String, dynamic>?> read() async {
    try {
      final value = preferences.getString(sessionKey);
      return value == null
          ? null
          : Map<String, dynamic>.from(jsonDecode(value));
    } on FormatException {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(Map<String, dynamic> value) async {
    await preferences.setString(sessionKey, jsonEncode(value));
  }

  @override
  Future<void> clear() async {
    await preferences.remove(sessionKey);
    await preferences.remove(demoRoleKey);
  }

  @override
  Future<String?> readDemoRole() async => preferences.getString(demoRoleKey);
}
