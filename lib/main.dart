import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();

  final settings = SettingsService();
  await settings.load();

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
