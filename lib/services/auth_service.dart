import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/user_profile.dart';
import 'database_service.dart';

/// IMPORTANT — read before using this in production:
/// This is a LOCAL, single-device login system. It proves "this is the
/// same person who signed up on this phone," not a secure, syncable
/// account system. There is no server, so:
///  - If the app's data is cleared or the phone is lost, the account
///    (and all health data) is gone — there's no recovery flow.
///  - It does not support using the same account on multiple devices.
/// For a real multi-device product, you'd move this to your backend
/// with proper password storage (e.g. bcrypt/argon2) and session tokens.
/// This is a reasonable starting point for a personal, single-user app.
class AuthService {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  static const _sessionKey = 'auth_current_profile_id';

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  Future<UserProfile> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final existing = await DatabaseService.instance.getProfileByEmail(email);
    if (existing != null) {
      throw Exception('An account with this email already exists.');
    }

    final profile = UserProfile(
      id: const Uuid().v4(),
      name: name,
      email: email,
      passwordHash: _hashPassword(password),
    );
    await DatabaseService.instance.insertProfile(profile);
    await _saveSession(profile.id);
    return profile;
  }

  Future<UserProfile> logIn({
    required String email,
    required String password,
  }) async {
    final profile = await DatabaseService.instance.getProfileByEmail(email);
    if (profile == null) {
      throw Exception('No account found with this email.');
    }
    if (profile.passwordHash != _hashPassword(password)) {
      throw Exception('Incorrect password.');
    }
    await _saveSession(profile.id);
    return profile;
  }

  Future<void> logOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  Future<UserProfile?> getCurrentProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_sessionKey);
    if (id == null) return null;
    return DatabaseService.instance.getProfileById(id);
  }

  Future<void> _saveSession(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, profileId);
  }
}
