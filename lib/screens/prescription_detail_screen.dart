import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/prescription.dart';
import '../services/database_service.dart';
import 'chatbot_screen.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';

class PrescriptionDetailScreen extends StatelessWidget {
  final Prescription prescription;
  const PrescriptionDetailScreen({super.key, required this.prescription});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().languageCode;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppText.t('report_details', lang)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: AppText.t('delete', lang),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(AppText.t('delete_report_q', lang)),
                  content: Text(AppText.t('delete_report_body', lang)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(AppText.t('cancel', lang))),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(AppText.t('delete', lang),
                          style: const TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await DatabaseService.instance.deletePrescription(prescription.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (File(prescription.imagePath).existsSync())
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(prescription.imagePath)),
            ),
          const SizedBox(height: 16),
          Text(AppText.t('scanned_on', lang).replaceFirst('{date}',
              '${prescription.dateAdded.day}/${prescription.dateAdded.month}/${prescription.dateAdded.year}')),
          const SizedBox(height: 16),
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
            child: Text(
              prescription.rawText.isEmpty
                  ? AppText.t('no_text_detected', lang)
                  : prescription.rawText,
            ),
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
                    initialContextLabel: AppText.t('scanned_report_from', lang).replaceFirst('{date}',
                        '${prescription.dateAdded.day}/${prescription.dateAdded.month}/${prescription.dateAdded.year}'),
                    initialContextText: prescription.rawText,
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
