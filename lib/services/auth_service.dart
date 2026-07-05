import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import 'ai_backend_service.dart';

/// Cloud-backed authentication. Unlike the original local-only version,
/// accounts now live in your backend's Postgres database (see
/// backend/auth.js + backend/schema.sql), which is what makes signup,
/// login, and password recovery work "from anywhere" rather than being
/// tied to one phone.
///
/// A JWT session token and a JSON snapshot of the profile are cached
/// locally (SharedPreferences) purely so the app has something to show
/// immediately on launch and can still display the profile if opened
/// offline — the backend remains the source of truth for anything
/// written via updateProfile/signUp/logIn.
class AuthService {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  static const _tokenKey = 'auth_token';
  static const _profileCacheKey = 'auth_profile_cache';

  String get _baseUrl => AiBackendService.baseUrl;

  Future<UserProfile> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/auth/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'email': email, 'password': password}),
    );

    if (res.statusCode == 409) {
      throw Exception('An account with this email already exists.');
    }
    if (res.statusCode != 200) {
      throw Exception('Could not create account. Please try again.');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return _saveSession(data['token'], data['profile']);
  }

  Future<UserProfile> logIn({
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (res.statusCode == 401) {
      throw Exception('Incorrect email or password.');
    }
    if (res.statusCode != 200) {
      throw Exception('Could not log in. Please try again.');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return _saveSession(data['token'], data['profile']);
  }

  /// Requests a password-reset code by email. Always succeeds from the
  /// caller's point of view (even if the email isn't registered) — see
  /// the comment in backend/auth.js for why.
  Future<void> forgotPassword(String email) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    if (res.statusCode != 200) {
      throw Exception('Something went wrong. Please try again.');
    }
  }

  /// Completes a password reset using the code emailed to the user.
  Future<void> resetPassword({
    required String code,
    required String newPassword,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': code, 'newPassword': newPassword}),
    );
    if (res.statusCode != 200) {
      throw Exception('That code is invalid or has expired.');
    }
  }

  Future<void> logOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_profileCacheKey);
  }

  /// Returns the cached profile for immediate display. Returns null if
  /// no one is logged in on this device.
  Future<UserProfile?> getCurrentProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_profileCacheKey);
    if (cached == null) return null;
    return _profileFromJson(jsonDecode(cached) as Map<String, dynamic>);
  }

  /// Pushes profile edits to the backend, then updates the local cache.
  /// Call this instead of writing to local storage directly, so changes
  /// actually persist to the account rather than just this device.
  Future<UserProfile> updateProfile(UserProfile updated) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not logged in.');

    final res = await http.put(
      Uri.parse('$_baseUrl/api/auth/me'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'name': updated.name,
        'age': updated.age,
        'weightKg': updated.weightKg,
        'heightCm': updated.heightCm,
        'gender': updated.gender,
        'bio': updated.bio,
        'photoPath': updated.photoPath,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception('Could not save changes. Please try again.');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final profile = _profileFromJson(data['profile'] as Map<String, dynamic>);
    await _cacheProfile(profile);
    return profile;
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<UserProfile> _saveSession(String token, Map<String, dynamic> profileJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    final profile = _profileFromJson(profileJson);
    await _cacheProfile(profile);
    return profile;
  }

  Future<void> _cacheProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileCacheKey, jsonEncode({
      'id': profile.id,
      'name': profile.name,
      'email': profile.email,
      'age': profile.age,
      'weightKg': profile.weightKg,
      'heightCm': profile.heightCm,
      'gender': profile.gender,
      'bio': profile.bio,
      'photoPath': profile.photoPath,
    }));
  }

  UserProfile _profileFromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'],
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      // Password hashes never come back from the backend and are never
      // checked locally anymore — the backend verifies passwords now.
      // This field only still exists on the model for backward
      // compatibility with code that constructs UserProfile directly.
      passwordHash: '',
      age: json['age'],
      weightKg: (json['weightKg'] as num?)?.toDouble(),
      heightCm: (json['heightCm'] as num?)?.toDouble(),
      gender: json['gender'],
      bio: json['bio'] ?? '',
      photoPath: json['photoPath'],
    );
  }
}
