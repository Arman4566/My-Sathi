import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/medical_report.dart';
import '../services/database_service.dart';
import 'report_upload_screen.dart';
import 'report_detail_screen.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';

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
    final lang = context.watch<SettingsService>().languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(AppText.t('my_reports', lang))),
      body: _reports.isEmpty
          ? Center(
              child: Text(
                AppText.t('no_reports', lang),
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
                        '${r.summary.isNotEmpty ? AppText.t("summarized_suffix", lang) : ""}'),
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
