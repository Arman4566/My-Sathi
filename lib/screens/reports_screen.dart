import 'package:flutter/material.dart';
import '../models/medical_report.dart';
import '../services/database_service.dart';
import 'report_upload_screen.dart';
import 'report_detail_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<MedicalReport> _reports = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await DatabaseService.instance.getMedicalReports();
    setState(() => _reports = list);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My reports')),
      body: _reports.isEmpty
          ? Center(
              child: Text(
                'No reports uploaded yet.\nTap + to add a lab report or document.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _reports.length,
              itemBuilder: (context, i) {
                final r = _reports[i];
                return Card(
                  child: ListTile(
                    leading:
                        const Icon(Icons.article_outlined, color: Color(0xFF5B7CFA)),
                    title: Text(r.title),
                    subtitle: Text(
                        '${r.uploadedDate.day}/${r.uploadedDate.month}/${r.uploadedDate.year}'
                        '${r.summary.isNotEmpty ? " • summarized" : ""}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ReportDetailScreen(report: r)),
                      );
                      _load();
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
              context, MaterialPageRoute(builder: (_) => const ReportUploadScreen()));
          _load();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
