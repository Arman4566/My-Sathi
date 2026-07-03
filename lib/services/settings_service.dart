import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds app-wide settings (theme + language) and persists them so they
/// survive app restarts. Wrap the app in a ChangeNotifierProvider using
/// this class, and call the setters from the Settings screen.
class SettingsService extends ChangeNotifier {
  static const _themeKey = 'settings_theme_mode';
  static const _langKey = 'settings_language';

  ThemeMode _themeMode = ThemeMode.light;
  String _languageCode = 'en'; // 'en' or 'hi'

  ThemeMode get themeMode => _themeMode;
  String get languageCode => _languageCode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString(_themeKey);
    _themeMode = savedTheme == 'dark' ? ThemeMode.dark : ThemeMode.light;
    _languageCode = prefs.getString(_langKey) ?? 'en';
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
}
