import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  String? _userRole;

  Future<AuthResponse?> signUpWithEmail(
    String email,
    String password,
    String firstName,
    String lastName, {
    String role = 'user',
  }) async {
    try {
      final authResponse = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'first_name': firstName, 'last_name': lastName},
      );

      if (authResponse.user == null) {
        throw Exception('User registration failed');
      }

      final loginResponse = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (loginResponse.session == null) {
        throw Exception('Authentication failed after sign up');
      }

      _userRole = role;
      await _saveSessionData(loginResponse.session!, role);

      final profileResponse = await _supabase.from('user_profiles').insert({
        'user_id': authResponse.user!.id,
        'first_name': firstName,
        'last_name': lastName,
        'role': role,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).select();

      if (profileResponse.isEmpty) {
        await _supabase.auth.signOut();
        throw Exception('Profile creation failed');
      }

      return authResponse;
    } on AuthException catch (e) {
      throw AuthException(e.message);
    } catch (e) {
      await _supabase.auth.signOut();
      await _clearSessionData();
      throw Exception('Registration failed: ${e.toString()}');
    }
  }

  Future<User?> getCurrentUser() async {
    try {
      return _supabase.auth.currentUser;
    } catch (e) {
      throw Exception('Error getting user: ${e.toString()}');
    }
  }

  Future<Session?> getSession() async {
    try {
      return _supabase.auth.currentSession;
    } catch (e) {
      throw Exception('Error getting session: ${e.toString()}');
    }
  }

  Future<AuthResponse?> signInWithEmail(String email, String password) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.session != null) {
        final userData = await _supabase
            .from('user_profiles')
            .select('role')
            .eq('user_id', response.session!.user.id)
            .single();
        
        _userRole = userData['role'] as String? ?? 'user';
        await _saveSessionData(response.session!, _userRole!);
      }

      return response;
    } on AuthException catch (e) {
      throw AuthException(e.message);
    } catch (e) {
      throw Exception('Login failed: ${e.toString()}');
    }
  }

  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
      await _clearSessionData();
      _userRole = null;
    } catch (e) {
      throw Exception('Logout failed: ${e.toString()}');
    }
  }

  Future<void> _saveSessionData(Session session, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', session.accessToken);
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('user_role', role);
  }

  Future<void> _clearSessionData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('user_role');
    await prefs.setBool('isLoggedIn', false);
  }

  Future<bool> hasSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
      final role = prefs.getString('user_role');

      if (isLoggedIn && accessToken != null && role != null) {
        final session = await getSession();
        _userRole = role;
        return session != null && session.accessToken == accessToken;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> recoverSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      _userRole = prefs.getString('user_role');

      if (accessToken != null) {
        await _supabase.auth.recoverSession(accessToken);
      }
    } catch (e) {
      throw Exception('Session recovery failed: ${e.toString()}');
    }
  }

  Future<void> updateProfile({
    required String userId,
    String? firstName,
    String? lastName,
    String? phone,
    String? avatarUrl,
    String? role,
  }) async {
    try {
      final updateData = {
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
        if (phone != null) 'phone': phone,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (role != null) 'role': role,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final response = await _supabase
          .from('user_profiles')
          .update(updateData)
          .eq('user_id', userId);

      if (response.error != null) {
        throw Exception('Error updating profile: ${response.error!.message}');
      }

      if (role != null) {
        _userRole = role;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_role', role);
      }
    } catch (e) {
      throw Exception('Profile update failed: ${e.toString()}');
    }
  }

  String? get userRole => _userRole;

  Future<bool> isEmployee() async {
    if (_userRole == null) {
      await recoverSession();
    }
    return _userRole == 'employee';
  }

  Future<bool> isUser() async {
    if (_userRole == null) {
      await recoverSession();
    }
    return _userRole == 'user' || _userRole == null;
  }

  Future<void> updateUserRole(String userId, String newRole) async {
    try {
      final response = await _supabase
          .from('user_profiles')
          .update({'role': newRole})
          .eq('user_id', userId);

      if (response.error != null) {
        throw Exception('Error updating role: ${response.error!.message}');
      }

      _userRole = newRole;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_role', newRole);
    } catch (e) {
      throw Exception('Role update failed: ${e.toString()}');
    }
  }

  Future<String?> getBarberId() async {
    final user = await getCurrentUser();
    if (user == null) return null;
    
    try {
      final response = await _supabase
          .from('barbers')
          .select('id')
          .eq('user_id', user.id)
          .single();
      
      return response['id'] as String;
    } catch (e) {
      debugPrint('Error getting barber ID: $e');
      return null;
    }
  }

  Future<bool> isBarber() async {
    if (_userRole == null) {
      await recoverSession();
    }
    return _userRole == 'barber';
  }
}