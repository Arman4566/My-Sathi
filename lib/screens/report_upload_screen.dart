import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/medical_report.dart';
import '../services/database_service.dart';
import '../services/ocr_service.dart';
import '../services/ai_backend_service.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';

class ReportUploadScreen extends StatefulWidget {
  const ReportUploadScreen({super.key});
  @override
  State<ReportUploadScreen> createState() => _ReportUploadScreenState();
}

class _ReportUploadScreenState extends State<ReportUploadScreen> {
  final _ocr = OcrService();
  final _picker = ImagePicker();
  final _titleCtrl = TextEditingController();

  File? _image;
  String _rawText = '';
  String? _summary;
  bool _loading = false;
  String? _error;

  Future<void> _pickImage(ImageSource source) async {
    final lang = context.read<SettingsService>().languageCode;
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    setState(() {
      _image = File(picked.path);
      _loading = true;
      _error = null;
      _summary = null;
    });

    try {
      final raw = await _ocr.extractRawText(picked.path);
      String? summary;
      try {
        summary = await AiBackendService.instance.summarizeReport(raw);
      } catch (_) {
        summary = null; // backend not reachable — still let them save the raw text
      }
      setState(() {
        _rawText = raw;
        _summary = summary;
        if (summary == null) {
          _error = AppText.t('summary_unavailable', lang);
        }
      });
    } catch (e) {
      setState(() => _error = AppText.t('could_not_read_photo_text', lang));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_image == null) return;
    final lang = context.read<SettingsService>().languageCode;
    final report = MedicalReport(
      id: const Uuid().v4(),
      title: _titleCtrl.text.trim().isEmpty
          ? AppText.t('report_dated_title', lang).replaceFirst('{date}',
              '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}')
          : _titleCtrl.text.trim(),
      filePath: _image!.path,
      rawText: _rawText,
      summary: _summary ?? '',
      uploadedDate: DateTime.now(),
    );
    await DatabaseService.instance.insertMedicalReport(report);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _ocr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(AppText.t('upload_report', lang))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                  labelText: AppText.t('title_hint', lang),
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
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
                    label: Text(AppText.t('take_photo', lang)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: Text(AppText.t('from_gallery', lang)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.orange)),
              ),
            if (_summary != null) ...[
              Text(AppText.t('ai_summary', lang), style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_summary!),
              ),
              const SizedBox(height: 8),
              Text(
                AppText.t('summary_disclaimer', lang),
                style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
              ),
            ],
            if (_image != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _save, child: Text(AppText.t('save_report', lang))),
            ],
          ],
        ),
      ),
    );
  }
}
