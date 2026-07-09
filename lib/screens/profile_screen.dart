import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await AuthService.instance.getCurrentProfile();
    setState(() {
      _profile = profile;
      _loading = false;
    });
  }

  Future<void> _pickPhoto() async {
    if (_profile == null) return;
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    try {
      final updated = await AuthService.instance
          .updateProfile(_profile!.copyWith(photoPath: picked.path));
      setState(() => _profile = updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  /// Small reusable "tap to edit" row, matching a WhatsApp-style profile
  /// screen: icon, label, current value, tap to change it.
  Future<void> _editField({
    required String label,
    required String currentValue,
    required void Function(String) onSave,
    TextInputType keyboardType = TextInputType.text,
  }) async {
    final ctrl = TextEditingController(text: currentValue);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit $label'),
        content: TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              onSave(ctrl.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfile(UserProfile updated) async {
    try {
      final saved = await AuthService.instance.updateProfile(updated);
      setState(() => _profile = saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
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

    final p = _profile!;
    final hasPhoto = p.photoPath != null && File(p.photoPath!).existsSync();
    final bmi = p.bmi;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 56,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  backgroundImage: hasPhoto ? FileImage(File(p.photoPath!)) : null,
                  child: hasPhoto
                      ? null
                      : Text(
                          p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                          style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: InkWell(
                    onTap: _pickPhoto,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFF5B7CFA),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => _editField(
                label: 'name',
                currentValue: p.name,
                onSave: (v) {
                  if (v.isNotEmpty) _saveProfile(p.copyWith(name: v));
                },
              ),
              child: const Text('Edit'),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          _infoRow(
            icon: Icons.person_outline,
            label: 'Name',
            value: p.name,
            onTap: () => _editField(
              label: 'name',
              currentValue: p.name,
              onSave: (v) {
                if (v.isNotEmpty) _saveProfile(p.copyWith(name: v));
              },
            ),
          ),
          _infoRow(
            icon: Icons.email_outlined,
            label: 'Email',
            value: p.email,
            onTap: null, // email is the account identifier — not editable here
          ),
          _infoRow(
            icon: Icons.cake_outlined,
            label: 'Age',
            value: p.age?.toString() ?? 'Not set',
            onTap: () => _editField(
              label: 'age',
              currentValue: p.age?.toString() ?? '',
              keyboardType: TextInputType.number,
              onSave: (v) => _saveProfile(p.copyWith(age: int.tryParse(v))),
            ),
          ),
          _infoRow(
            icon: Icons.monitor_weight_outlined,
            label: 'Weight (kg)',
            value: p.weightKg?.toString() ?? 'Not set',
            onTap: () => _editField(
              label: 'weight (kg)',
              currentValue: p.weightKg?.toString() ?? '',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onSave: (v) => _saveProfile(p.copyWith(weightKg: double.tryParse(v))),
            ),
          ),
          _infoRow(
            icon: Icons.height,
            label: 'Height (cm)',
            value: p.heightCm?.toString() ?? 'Not set',
            onTap: () => _editField(
              label: 'height (cm)',
              currentValue: p.heightCm?.toString() ?? '',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onSave: (v) => _saveProfile(p.copyWith(heightCm: double.tryParse(v))),
            ),
          ),
          _infoRow(
            icon: Icons.wc,
            label: 'Gender',
            value: p.gender ?? 'Not set',
            onTap: () async {
              final choice = await showDialog<String>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: const Text('Gender'),
                  children: [
                    for (final g in ['Female', 'Male', 'Other'])
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, g),
                        child: Text(g),
                      ),
                  ],
                ),
              );
              if (choice != null) _saveProfile(p.copyWith(gender: choice));
            },
          ),
          if (bmi != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('BMI: ${bmi.toStringAsFixed(1)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).hintColor),
      title: Text(label, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
      subtitle: Text(value, style: const TextStyle(fontSize: 16)),
      trailing: onTap != null ? const Icon(Icons.chevron_right) : null,
      onTap: onTap,
    );
  }
}
