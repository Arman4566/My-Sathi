import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  final _ageCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  String? _gender;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await AuthService.instance.getCurrentProfile();
    setState(() {
      _profile = profile;
      _ageCtrl.text = profile?.age?.toString() ?? '';
      _weightCtrl.text = profile?.weightKg?.toString() ?? '';
      _heightCtrl.text = profile?.heightCm?.toString() ?? '';
      _gender = profile?.gender;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_profile == null) return;
    setState(() => _saving = true);

    final updated = _profile!.copyWith(
      age: int.tryParse(_ageCtrl.text),
      weightKg: double.tryParse(_weightCtrl.text),
      heightCm: double.tryParse(_heightCtrl.text),
      gender: _gender,
    );
    await DatabaseService.instance.updateProfile(updated);

    setState(() {
      _profile = updated;
      _saving = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile updated')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_profile == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    final bmi = _profile!.bmi;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: const Color(0xFFEEF1FF),
              child: Text(
                _profile!.name.isNotEmpty ? _profile!.name[0].toUpperCase() : '?',
                style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5B7CFA)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
              child: Text(_profile!.name,
                  style:
                      const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          Center(
              child: Text(_profile!.email,
                  style: TextStyle(color: Colors.grey.shade600))),
          const SizedBox(height: 28),
          TextField(
            controller: _ageCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Age', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _weightCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Weight (kg)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _heightCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Height (cm)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _gender,
            decoration: const InputDecoration(
                labelText: 'Gender', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'Female', child: Text('Female')),
              DropdownMenuItem(value: 'Male', child: Text('Male')),
              DropdownMenuItem(value: 'Other', child: Text('Other')),
            ],
            onChanged: (v) => setState(() => _gender = v),
          ),
          if (bmi != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF1FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('BMI: ${bmi.toStringAsFixed(1)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child:
                        CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save changes'),
          ),
        ],
      ),
    );
  }
}
