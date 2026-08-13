import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/prescription.dart';
import '../services/database_service.dart';
import 'prescription_detail_screen.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';

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
    final lang = context.watch<SettingsService>().languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(AppText.t('reports_and_prescriptions', lang))),
      body: _prescriptions.isEmpty
          ? Center(
              child: Text(
                AppText.t('no_scanned_yet', lang),
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
                        ? AppText.t('scanned_document', lang)
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
