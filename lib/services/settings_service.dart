import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds app-wide settings (theme + language + reminder sound) and
/// persists them so they survive app restarts. Wrap the app in a
/// ChangeNotifierProvider using this class, and call the setters from
/// the Settings screen.
class SettingsService extends ChangeNotifier {
  static const _themeKey = 'settings_theme_mode';
  static const _langKey = 'settings_language';
  // Public so NotificationService can read the same value directly via
  // SharedPreferences when scheduling an alarm, without needing a
  // BuildContext/Provider at that point.
  static const soundEnabledKey = 'settings_alarm_sound_enabled';

  ThemeMode _themeMode = ThemeMode.light;
  String _languageCode = 'en'; // 'en' or 'hi'
  bool _soundEnabled = true;

  ThemeMode get themeMode => _themeMode;
  String get languageCode => _languageCode;
  bool get soundEnabled => _soundEnabled;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString(_themeKey);
    _themeMode = savedTheme == 'dark' ? ThemeMode.dark : ThemeMode.light;
    _languageCode = prefs.getString(_langKey) ?? 'en';
    _soundEnabled = prefs.getBool(soundEnabledKey) ?? true;
    notifyListeners();
  }

  Future<void> setDarkMode(bool isDark) async {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, isDark ? 'dark' : 'light');
  }

  Future<void> setLanguage(String code) async {
    _languageCode = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langKey, code);
  }

  Future<void> setSoundEnabled(bool enabled) async {
    _soundEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(soundEnabledKey, enabled);
  }
}
