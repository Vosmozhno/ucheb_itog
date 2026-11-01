import 'package:flutter/foundation.dart';
import '../core/api_error.dart';
import '../core/config.dart';
import '../core/supabase_api.dart';
import '../models/app_role.dart';
import '../repositories/session_store.dart';

class AuthState extends ChangeNotifier {
  AuthState(
    this.api,
    this.store, {
    this.allowRoleDemo = AppConfig.authRoleDemo,
  }) {
    api.accessToken = _token;
    api.refreshSession = refresh;
    api.sessionExpired = expire;
  }
  final SupabaseApi api;
  final SessionStore store;
  final bool allowRoleDemo;
  UserProfile? profile;
  Map<String, dynamic>? _session;
  String? _demoRole;
  Future<bool>? _refreshing;
  bool ready = false;
  ApiError? startupError;
  bool get signedIn => profile != null;
  AppRole get role => allowRoleDemo && _demoRole != null
      ? AppRole.parse(_demoRole)
      : profile?.role ?? AppRole.client;
  bool get hasDemoOverride =>
      allowRoleDemo && _demoRole != null && role != profile?.role;
  String? get userId => profile?.id;
  Future<void> restore() async {
    ready = false;
    startupError = null;
    notifyListeners();
    try {
      _session = await store.read();
      if (allowRoleDemo) _demoRole = await store.readDemoRole();
      if (_session != null) {
        final token = await _token();
        if (token != null) {
          try {
            await _loadProfile();
          } on ApiError catch (error) {
            final cached = _session?['profile'];
            if (error.canRetry && cached is Map) {
              profile = UserProfile.fromJson(Map<String, dynamic>.from(cached));
            } else {
              rethrow;
            }
          }
        }
      }
    } on ApiError catch (error) {
      if (error.kind == ApiErrorKind.unauthorized) {
        await expire();
      } else {
        startupError = error;
      }
    } on Object {
      await expire();
    } finally {
      ready = true;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    final response = await api.request(
      '/auth/v1/token',
      method: 'POST',
      authenticated: false,
      query: {'grant_type': 'password'},
      data: {'email': email.trim().toLowerCase(), 'password': password},
    );
    _setTokens(Map<String, dynamic>.from(response.data));
    _demoRole = null;
    await _loadProfile();
    ready = true;
    startupError = null;
    notifyListeners();
  }

  Future<bool> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) async {
    final response = await api.request(
      '/auth/v1/signup',
      method: 'POST',
      authenticated: false,
      data: {
        'email': email.trim().toLowerCase(),
        'password': password,
        'data': {'full_name': fullName.trim(), 'phone': phone.trim()},
      },
    );
    final data = Map<String, dynamic>.from(response.data);
    if (data['access_token'] != null) {
      _setTokens(data);
      await _loadProfile();
      ready = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  void _setTokens(Map<String, dynamic> data) {
    _session = {
      'access_token': data['access_token'],
      'refresh_token': data['refresh_token'],
      'expires_at':
          data['expires_at'] ??
          DateTime.now().millisecondsSinceEpoch ~/ 1000 +
              (data['expires_in'] as num? ?? 3600).toInt(),
      'user_id': (data['user'] as Map?)?['id'] ?? _session?['user_id'],
      if (_session?['profile'] != null) 'profile': _session!['profile'],
    };
  }

  Future<String?> _token() async {
    if (_session == null) return null;
    final expires = (_session!['expires_at'] as num?)?.toInt() ?? 0;
    if (expires <= DateTime.now().millisecondsSinceEpoch ~/ 1000 + 30) {
      if (!await refresh()) return null;
    }
    return _session?['access_token'] as String?;
  }

  Future<bool> refresh() =>
      _refreshing ??= _performRefresh().whenComplete(() => _refreshing = null);
  Future<bool> _performRefresh() async {
    final refreshToken = _session?['refresh_token'];
    if (refreshToken == null) return false;
    try {
      final response = await api.request(
        '/auth/v1/token',
        method: 'POST',
        authenticated: false,
        query: {'grant_type': 'refresh_token'},
        data: {'refresh_token': refreshToken},
      );
      _setTokens(Map<String, dynamic>.from(response.data));
      await store.write(_session!);
      return true;
    } on ApiError catch (error) {
      if (error.canRetry) rethrow;
      await expire();
      return false;
    }
  }

  Future<void> _loadProfile() async {
    final id = _session?['user_id'];
    final response = await api.request(
      '/rest/v1/profiles',
      query: {'select': 'id,full_name,role', 'id': 'eq.$id', 'limit': 1},
    );
    final data = response.data as List;
    if (data.isEmpty) {
      throw const ApiError(
        ApiErrorKind.forbidden,
        'Профиль отсутствует. Обратитесь к администратору.',
      );
    }
    profile = UserProfile.fromJson(Map<String, dynamic>.from(data.first));
    _session!['profile'] = {
      'id': profile!.id,
      'full_name': profile!.fullName,
      'role': profile!.role.code,
    };
    await store.write(_session!);
  }

  Future<void> reloadProfile() async {
    await _loadProfile();
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.request(
        '/auth/v1/logout',
        method: 'POST',
        query: {'scope': 'local'},
      );
    } on ApiError {
      /* Always remove the local session even if the network is down. */
    } finally {
      await expire();
    }
  }

  Future<void> expire() async {
    _session = null;
    profile = null;
    _demoRole = null;
    startupError = null;
    await store.clear();
    notifyListeners();
  }
}
