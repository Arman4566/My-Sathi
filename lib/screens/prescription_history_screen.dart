import 'package:flutter/material.dart';
import '../models/prescription.dart';
import '../services/database_service.dart';
import 'prescription_detail_screen.dart';

class PrescriptionHistoryScreen extends StatefulWidget {
  const PrescriptionHistoryScreen({super.key});
  @override
  State<PrescriptionHistoryScreen> createState() =>
      _PrescriptionHistoryScreenState();
}

class _PrescriptionHistoryScreenState extends State<PrescriptionHistoryScreen> {
  List<Prescription> _prescriptions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await DatabaseService.instance.getPrescriptions();
    setState(() => _prescriptions = list);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports & prescriptions')),
      body: _prescriptions.isEmpty
          ? Center(
              child: Text(
                'No scanned prescriptions or reports yet.',
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _prescriptions.length,
              itemBuilder: (context, i) {
                final p = _prescriptions[i];
                return Card(
                  child: ListTile(
                    leading:
                        const Icon(Icons.description_outlined, color: Color(0xFF5B7CFA)),
                    title: Text(p.doctorName.isEmpty
                        ? 'Scanned document'
                        : 'Dr. ${p.doctorName}'),
                    subtitle: Text(
                        '${p.dateAdded.day}/${p.dateAdded.month}/${p.dateAdded.year}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => PrescriptionDetailScreen(prescription: p)),
                      );
                      _load();
                    },
                  ),
                );
              },
            ),
    );
  }
}
