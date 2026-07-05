import 'package:flutter/material.dart';
import '../services/auth_service.dart';
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
        _info = 'If that email is registered, a 6-digit code has been sent. '
            'It expires in 15 minutes.';
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_codeCtrl.text.trim().isEmpty || _newPasswordCtrl.text.length < 4) {
      setState(() => _error = 'Enter the code and a password of at least 4 characters.');
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
            const SnackBar(content: Text('Password updated. Please log in.')));
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
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_codeSent) ...[
                const Text(
                  "Enter your account email and we'll send you a 6-digit reset code.",
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Email', border: OutlineInputBorder()),
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
                      : const Text('Send reset code'),
                ),
              ] else ...[
                if (_info != null) ...[
                  Text(_info!, style: TextStyle(color: Theme.of(context).hintColor)),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: '6-digit code', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _newPasswordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'New password', border: OutlineInputBorder()),
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
                      : const Text('Reset password'),
                ),
                TextButton(
                  onPressed: () => setState(() => _codeSent = false),
                  child: const Text('Use a different email'),
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
