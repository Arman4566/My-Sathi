import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';
import 'login_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();

  bool _codeSent = false;
  bool _loading = false;
  String? _error;
  String? _info;

  Future<void> _requestCode() async {
    if (_emailCtrl.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.instance.forgotPassword(_emailCtrl.text.trim());
      setState(() {
        _codeSent = true;
        _info = AppText.t('code_sent_info', context.read<SettingsService>().languageCode);
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_codeCtrl.text.trim().isEmpty || _newPasswordCtrl.text.length < 4) {
      setState(() => _error = AppText.t('enter_code_password', context.read<SettingsService>().languageCode));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.instance.resetPassword(
        code: _codeCtrl.text.trim(),
        newPassword: _newPasswordCtrl.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppText.t('password_updated_login', context.read<SettingsService>().languageCode))));
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(AppText.t('reset_password', lang))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_codeSent) ...[
                Text(AppText.t('enter_email_reset_note', lang)),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                      labelText: AppText.t('email', lang), border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loading ? null : _requestCode,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(AppText.t('send_reset_code', lang)),
                ),
              ] else ...[
                if (_info != null) ...[
                  Text(_info!, style: TextStyle(color: Theme.of(context).hintColor)),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: AppText.t('six_digit_code', lang), border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _newPasswordCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: AppText.t('new_password', lang), border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loading ? null : _resetPassword,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(AppText.t('reset_password', lang)),
                ),
                TextButton(
                  onPressed: () => setState(() => _codeSent = false),
                  child: Text(AppText.t('use_different_email', lang)),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
