import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/medical_report.dart';
import '../services/database_service.dart';
import 'chatbot_screen.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';

class ReportDetailScreen extends StatelessWidget {
  final MedicalReport report;
  const ReportDetailScreen({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().languageCode;
    return Scaffold(
      appBar: AppBar(
        title: Text(report.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(AppText.t('delete_report_q', lang)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(AppText.t('cancel', lang))),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child:
                          Text(AppText.t('delete', lang), style: const TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await DatabaseService.instance.deleteMedicalReport(report.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (File(report.filePath).existsSync())
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(report.filePath)),
            ),
          const SizedBox(height: 16),
          Text(AppText.t('uploaded_on', lang).replaceFirst('{date}',
              '${report.uploadedDate.day}/${report.uploadedDate.month}/${report.uploadedDate.year}')),
          const SizedBox(height: 16),
          if (report.summary.isNotEmpty) ...[
            Text(AppText.t('ai_summary', lang), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(report.summary),
            ),
            const SizedBox(height: 16),
          ],
          Text(AppText.t('extracted_text', lang), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Text(report.rawText.isEmpty ? AppText.t('no_text_detected', lang) : report.rawText),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.chat_bubble_outline),
            label: Text(AppText.t('discuss_with_assistant', lang)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatbotScreen(
                    initialContextLabel: report.title,
                    initialContextText: report.rawText,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
