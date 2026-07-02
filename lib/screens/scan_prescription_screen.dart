import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/medicine.dart';
import '../models/prescription.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/ocr_service.dart';

class ScanPrescriptionScreen extends StatefulWidget {
  const ScanPrescriptionScreen({super.key});
  @override
  State<ScanPrescriptionScreen> createState() => _ScanPrescriptionScreenState();
}

class _ScanPrescriptionScreenState extends State<ScanPrescriptionScreen> {
  final _ocr = OcrService();
  final _picker = ImagePicker();

  File? _image;
  String _rawText = '';
  List<ParsedMedicineSuggestion> _suggestions = [];
  bool _loading = false;
  String? _error;

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    setState(() {
      _image = File(picked.path);
      _loading = true;
      _error = null;
      _suggestions = [];
    });

    try {
      final raw = await _ocr.extractRawText(picked.path);
      final suggestions = await _ocr.scanAndParse(picked.path);
      setState(() {
        _rawText = raw;
        _suggestions = suggestions;
        if (suggestions.isEmpty) {
          _error =
              'No medicines could be detected in this photo. You can add them manually from the "My medicines" screen instead.';
        }
      });
    } catch (e) {
      setState(() => _error =
          'Could not read this prescription automatically. You can still add medicines manually from the "My medicines" screen.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _confirmAndSave() async {
    if (_image == null) return;
    final prescriptionId = const Uuid().v4();

    await DatabaseService.instance.insertPrescription(Prescription(
      id: prescriptionId,
      imagePath: _image!.path,
      rawText: _rawText,
      doctorName: '',
      dateAdded: DateTime.now(),
    ));

    for (final s in _suggestions) {
      final medicine = Medicine(
        id: const Uuid().v4(),
        name: s.name,
        dosage: s.dosage,
        instructions: s.instructions,
        times: s.suggestedTimes.isNotEmpty ? s.suggestedTimes : ['09:00'],
        startDate: DateTime.now(),
        prescriptionId: prescriptionId,
      );
      await DatabaseService.instance.insertMedicine(medicine);
      await NotificationService.instance.scheduleMedicineReminders(medicine);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _ocr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan prescription')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(_image!, height: 200, fit: BoxFit.cover),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Take photo'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('From gallery'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.orange)),
            if (_suggestions.isNotEmpty) ...[
              const Text('Please review before saving',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'AI reading of handwriting isn\'t perfect — check each medicine, dose, and time below and fix anything that looks wrong.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: _suggestions.length,
                  itemBuilder: (context, i) {
                    final s = _suggestions[i];
                    return Card(
                      child: ListTile(
                        title: Text(s.name.isEmpty ? '(name unclear)' : s.name),
                        subtitle: Text(
                            '${s.dosage} • ${s.instructions}\nTimes: ${s.suggestedTimes.join(", ")}'),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _confirmAndSave,
                child: const Text('Confirm & save'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
