import 'package:flutter/material.dart';
import '../models/medicine.dart';
import '../models/appointment.dart';
import '../services/database_service.dart';
import 'scan_prescription_screen.dart';
import 'medicine_list_screen.dart';
import 'appointments_screen.dart';
import 'chatbot_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Medicine> _medicines = [];
  List<Appointment> _appointments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final meds = await DatabaseService.instance.getActiveMedicines();
    final appts = await DatabaseService.instance.getUpcomingAppointments();
    setState(() {
      _medicines = meds;
      _appointments = appts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final nextAppt = _appointments.isNotEmpty ? _appointments.first : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text('Good day 👋',
                        style: TextStyle(
                            fontSize: 26, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Here is your health summary for today',
                        style: TextStyle(color: Colors.grey.shade600)),
                    const SizedBox(height: 24),

                    if (nextAppt != null) _nextAppointmentCard(nextAppt),
                    const SizedBox(height: 20),

                    const Text('Today\'s medicines',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    if (_medicines.isEmpty)
                      _emptyMedicinesCard()
                    else
                      ..._medicines.map(_medicineCard),

                    const SizedBox(height: 24),
                    _quickActionsRow(context),
                  ],
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ScanPrescriptionScreen()));
          _load();
        },
        icon: const Icon(Icons.camera_alt),
        label: const Text('Scan prescription'),
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

  Widget _emptyMedicinesCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.medication_outlined, color: Colors.grey.shade400),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No medicines yet. Scan a prescription to get started.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _medicineCard(Medicine m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF1FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.medication, color: Color(0xFF5B7CFA)),
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
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionsRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            context,
            icon: Icons.list_alt,
            label: 'My medicines',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MedicineListScreen())),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _actionButton(
            context,
            icon: Icons.calendar_month,
            label: 'Appointments',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AppointmentsScreen())),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _actionButton(
            context,
            icon: Icons.chat_bubble_outline,
            label: 'Ask assistant',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ChatbotScreen())),
          ),
        ),
      ],
    );
  }

  Widget _actionButton(BuildContext context,
      {required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
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
    );
  }
}
