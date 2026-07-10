import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // CRITICAL: notification setup varies a lot across Android versions and
  // manufacturers (we've already hit two separate permission-related
  // crashes here on just one test device). If this throws on some other
  // phone and isn't caught, the app dies before any screen ever renders —
  // "installs but won't open," with no error visible to the user. Worst
  // case if this fails: reminders may not work on that device, but the
  // app itself must always be able to open.
  try {
    await NotificationService.instance.init();
  } catch (e) {
    debugPrint('Notification init failed (app will still open): $e');
  }

  final settings = SettingsService();
  try {
    await settings.load();
  } catch (e) {
    debugPrint('Settings load failed, using defaults: $e');
  }

  runApp(
    ChangeNotifierProvider.value(
      value: settings,
      child: const PatientCareApp(),
    ),
  );
}

class PatientCareApp extends StatelessWidget {
  const PatientCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return MaterialApp(
      title: 'Sathi',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      // Every screen should read colors from Theme.of(context) rather than
      // hardcoding Colors.white / a fixed hex background — that's what
      // makes dark mode apply consistently across the whole app instead
      // of only the screens that happen to use default Material colors.
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF5B7CFA),
        scaffoldBackgroundColor: const Color(0xFFF6F8FB),
        cardColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF6F8FB),
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF5B7CFA),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF5B7CFA),
        scaffoldBackgroundColor: const Color(0xFF121318),
        cardColor: const Color(0xFF1E2028),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121318),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF5B7CFA),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
