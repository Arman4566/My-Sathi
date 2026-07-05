import 'dart:io';
import 'package:flutter/material.dart';
import '../models/medical_report.dart';
import '../services/database_service.dart';
import 'chatbot_screen.dart';

class ReportDetailScreen extends StatelessWidget {
  final MedicalReport report;
  const ReportDetailScreen({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
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
                  title: const Text('Delete this report?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child:
                          const Text('Delete', style: TextStyle(color: Colors.red)),
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
          Text(
              'Uploaded ${report.uploadedDate.day}/${report.uploadedDate.month}/${report.uploadedDate.year}'),
          const SizedBox(height: 16),
          if (report.summary.isNotEmpty) ...[
            const Text('AI summary', style: TextStyle(fontWeight: FontWeight.bold)),
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
          const Text('Extracted text', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Text(report.rawText.isEmpty ? '(no text detected)' : report.rawText),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Discuss this report with the assistant'),
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
