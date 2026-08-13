import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';

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
    final lang = context.read<SettingsService>().languageCode;
    final ctrl = TextEditingController(text: currentValue);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppText.t('edit_field', lang).replaceFirst('{field}', label)),
        content: TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppText.t('cancel', lang))),
          ElevatedButton(
            onPressed: () {
              onSave(ctrl.text.trim());
              Navigator.pop(ctx);
            },
            child: Text(AppText.t('save', lang)),
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
    final lang = context.watch<SettingsService>().languageCode;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_profile == null) {
      return Scaffold(body: Center(child: Text(AppText.t('not_logged_in', lang))));
    }

    final p = _profile!;
    final hasPhoto = p.photoPath != null && File(p.photoPath!).existsSync();
    final bmi = p.bmi;

    return Scaffold(
      appBar: AppBar(title: Text(AppText.t('profile', lang))),
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
                label: AppText.t('name', lang),
                currentValue: p.name,
                onSave: (v) {
                  if (v.isNotEmpty) _saveProfile(p.copyWith(name: v));
                },
              ),
              child: Text(AppText.t('edit', lang)),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          _infoRow(
            icon: Icons.person_outline,
            label: AppText.t('name', lang),
            value: p.name,
            onTap: () => _editField(
              label: AppText.t('name', lang),
              currentValue: p.name,
              onSave: (v) {
                if (v.isNotEmpty) _saveProfile(p.copyWith(name: v));
              },
            ),
          ),
          _infoRow(
            icon: Icons.email_outlined,
            label: AppText.t('email', lang),
            value: p.email,
            onTap: null, // email is the account identifier — not editable here
          ),
          _infoRow(
            icon: Icons.cake_outlined,
            label: AppText.t('age', lang),
            value: p.age?.toString() ?? AppText.t('not_set', lang),
            onTap: () => _editField(
              label: AppText.t('age', lang),
              currentValue: p.age?.toString() ?? '',
              keyboardType: TextInputType.number,
              onSave: (v) => _saveProfile(p.copyWith(age: int.tryParse(v))),
            ),
          ),
          _infoRow(
            icon: Icons.monitor_weight_outlined,
            label: AppText.t('weight_kg', lang),
            value: p.weightKg?.toString() ?? AppText.t('not_set', lang),
            onTap: () => _editField(
              label: AppText.t('weight_kg', lang),
              currentValue: p.weightKg?.toString() ?? '',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onSave: (v) => _saveProfile(p.copyWith(weightKg: double.tryParse(v))),
            ),
          ),
          _infoRow(
            icon: Icons.height,
            label: AppText.t('height_cm', lang),
            value: p.heightCm?.toString() ?? AppText.t('not_set', lang),
            onTap: () => _editField(
              label: AppText.t('height_cm', lang),
              currentValue: p.heightCm?.toString() ?? '',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onSave: (v) => _saveProfile(p.copyWith(heightCm: double.tryParse(v))),
            ),
          ),
          _infoRow(
            icon: Icons.wc,
            label: AppText.t('gender', lang),
            value: p.gender ?? AppText.t('not_set', lang),
            onTap: () async {
              final options = {
                'Female': AppText.t('female', lang),
                'Male': AppText.t('male', lang),
                'Other': AppText.t('other', lang),
              };
              final choice = await showDialog<String>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: Text(AppText.t('gender', lang)),
                  children: [
                    for (final g in options.entries)
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, g.key),
                        child: Text(g.value),
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
                child: Text(
                    AppText.t('bmi_label', lang)
                        .replaceFirst('{value}', bmi.toStringAsFixed(1)),
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
