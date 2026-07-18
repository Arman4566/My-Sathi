import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Reminder diagnostics',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).hintColor)),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Send test notification now'),
            subtitle: const Text(
                "If this doesn't appear, notifications are blocked for this "
                "app in phone settings — check that first."),
            onTap: () async {
              try {
                await NotificationService.instance.sendTestNotificationNow();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Sent — check your notification shade now.')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Failed: $e')));
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.alarm),
            title: const Text('Send test reminder in 30 seconds'),
            subtitle: const Text(
                "Uses the exact same scheduling as real reminders. If the "
                "notification above works but this never appears, it's a "
                "scheduled-delivery issue (battery/background restrictions) "
                "rather than notifications being blocked outright."),
            onTap: () async {
              try {
                await NotificationService.instance
                    .sendTestReminderIn(const Duration(seconds: 30));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          'Scheduled — lock your phone and wait 30 seconds.')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Failed: $e')));
                }
              }
            },
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
