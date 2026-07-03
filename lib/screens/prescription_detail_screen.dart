import 'dart:io';
import 'package:flutter/material.dart';
import '../models/prescription.dart';
import '../services/database_service.dart';
import 'chatbot_screen.dart';

class PrescriptionDetailScreen extends StatelessWidget {
  final Prescription prescription;
  const PrescriptionDetailScreen({super.key, required this.prescription});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete this report?'),
                  content: const Text(
                      'This removes it from your records. It won\'t affect any medicine reminders already saved.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete',
                          style: TextStyle(color: Colors.red)),
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
          Text('Scanned on '
              '${prescription.dateAdded.day}/${prescription.dateAdded.month}/${prescription.dateAdded.year}'),
          const SizedBox(height: 16),
          const Text('Extracted text', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              prescription.rawText.isEmpty
                  ? '(no text detected)'
                  : prescription.rawText,
            ),
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
                    initialContextLabel:
                        'Scanned report from ${prescription.dateAdded.day}/${prescription.dateAdded.month}/${prescription.dateAdded.year}',
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
