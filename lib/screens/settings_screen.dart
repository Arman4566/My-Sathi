import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';
import '../services/app_text.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final lang = settings.languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(AppText.t('settings', lang))),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text(AppText.t('dark_mode', lang)),
            secondary: const Icon(Icons.dark_mode_outlined),
            value: settings.themeMode == ThemeMode.dark,
            onChanged: (v) => settings.setDarkMode(v),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(AppText.t('language', lang)),
            trailing: DropdownButton<String>(
              value: settings.languageCode,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'hi', child: Text('हिन्दी')),
              ],
              onChanged: (code) {
                if (code != null) settings.setLanguage(code);
              },
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: Text(AppText.t('logout', lang),
                style: const TextStyle(color: Colors.redAccent)),
            onTap: () async {
              await AuthService.instance.logOut();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
