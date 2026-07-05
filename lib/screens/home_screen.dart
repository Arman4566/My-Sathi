import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/medicine.dart';
import '../models/appointment.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';
import 'scan_prescription_screen.dart';
import 'medicine_list_screen.dart';
import 'appointments_screen.dart';
import 'chatbot_screen.dart';
import 'prescription_history_screen.dart';
import 'reports_screen.dart';
import 'health_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Medicine> _medicines = [];
  List<Appointment> _appointments = [];
  String _userName = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final meds = await DatabaseService.instance.getActiveMedicines();
    final appts = await DatabaseService.instance.getUpcomingAppointments();
    final profile = await AuthService.instance.getCurrentProfile();
    setState(() {
      _medicines = meds;
      _appointments = appts;
      _userName = profile?.name ?? '';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().languageCode;
    final nextAppt = _appointments.isNotEmpty ? _appointments.first : null;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: AppText.t('profile', lang),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: AppText.t('settings', lang),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
                  children: [
                    Text(
                        _userName.isNotEmpty
                            ? '${AppText.t('good_day', lang)}, $_userName 👋'
                            : '${AppText.t('good_day', lang)} 👋',
                        style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(AppText.t('health_summary', lang),
                        style: TextStyle(color: theme.hintColor)),
                    const SizedBox(height: 24),
                    if (nextAppt != null) _nextAppointmentCard(nextAppt),
                    const SizedBox(height: 20),
                    Text(AppText.t('todays_medicines', lang),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    if (_medicines.isEmpty)
                      _emptyMedicinesCard(lang)
                    else
                      ..._medicines.map(_medicineCard),
                    const SizedBox(height: 24),
                    _quickActionsGrid(context, lang),
                  ],
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const ChatbotScreen())),
        icon: const Icon(Icons.chat_bubble_outline),
        label: Text(AppText.t('ask_assistant', lang)),
      ),
    );
  }

  Widget _nextAppointmentCard(Appointment a) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF5B7CFA), Color(0xFF7B61FF)]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_available, color: Colors.white, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Upcoming appointment',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                Text('Dr. ${a.doctorName}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                Text(
                  '${a.dateTime.day}/${a.dateTime.month} at '
                  '${a.dateTime.hour.toString().padLeft(2, '0')}:${a.dateTime.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyMedicinesCard(String lang) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(Icons.medication_outlined, color: Theme.of(context).hintColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppText.t('no_medicines', lang),
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _medicineCard(Medicine m) {
    final hasPhoto = m.photoPath != null && File(m.photoPath!).existsSync();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: hasPhoto
                  ? Image.file(File(m.photoPath!),
                      width: 44, height: 44, fit: BoxFit.cover)
                  : Container(
                      width: 44,
                      height: 44,
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(Icons.medication,
                          color: Theme.of(context).colorScheme.primary),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.name,
                      style:
                          const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  Text('${m.dosage} • ${m.times.join(", ")}',
                      style:
                          TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActionsGrid(BuildContext context, String lang) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _actionButton(
                context,
                icon: Icons.list_alt,
                label: AppText.t('my_medicines', lang),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const MedicineListScreen())),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionButton(
                context,
                icon: Icons.calendar_month,
                label: AppText.t('appointments', lang),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AppointmentsScreen())),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionButton(
                context,
                icon: Icons.camera_alt_outlined,
                label: AppText.t('scan_prescription', lang),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ScanPrescriptionScreen())),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _actionButton(
                context,
                icon: Icons.description_outlined,
                label: 'Prescriptions',
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PrescriptionHistoryScreen())),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionButton(
                context,
                icon: Icons.monitor_heart_outlined,
                label: AppText.t('my_health', lang),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const HealthScreen())),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionButton(
                context,
                icon: Icons.article_outlined,
                label: AppText.t('reports', lang),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ReportsScreen())),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _actionButton(BuildContext context,
      {required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: const Color(0xFF5B7CFA)),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
