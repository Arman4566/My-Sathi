import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/medical_report.dart';
import '../services/database_service.dart';
import '../services/ai_backend_service.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';

/// "Sathi AI Scan Insight" — patient uploads a photo of an X-ray,
/// ultrasound, or similar scan and gets back a themed, plain-language
/// AI-assisted description, which can then be saved into their reports
/// (reuses the existing MedicalReport model/table — see
/// DatabaseService.insertMedicalReport and ReportDetailScreen).
///
/// Deliberately does NOT show a confidence percentage, a risk grade
/// (e.g. "Critical"/"Severe"), or a fabricated heatmap — see the long
/// comment on SCAN_ANALYSIS_PROMPT in backend/server.js for why: Gemini
/// is a general vision model, not a regulator-validated diagnostic
/// imaging classifier, and inventing that kind of precision would be
/// actively misleading rather than helpful.
class ScanAnalysisScreen extends StatefulWidget {
  const ScanAnalysisScreen({super.key});
  @override
  State<ScanAnalysisScreen> createState() => _ScanAnalysisScreenState();
}

class _ScanAnalysisScreenState extends State<ScanAnalysisScreen> {
  final _picker = ImagePicker();
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  static const _scanTypes = ['X-ray', 'Ultrasound', 'Other scan'];
  String _scanType = _scanTypes.first;

  File? _image;
  ScanAnalysis? _analysis;
  bool _loading = false;
  String? _error;

  String _mimeTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _pickImage(ImageSource source) async {
    final lang = context.read<SettingsService>().languageCode;
    final picked = await _picker.pickImage(source: source, imageQuality: 80);
    if (picked == null) return;

    setState(() {
      _image = File(picked.path);
      _analysis = null;
      _error = null;
    });
    await _analyze();
    if (!mounted) return;
    if (_analysis == null && _error == null) {
      setState(() => _error = AppText.t('scan_analysis_unavailable', lang));
    }
  }

  Future<void> _analyze() async {
    if (_image == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await _image!.readAsBytes();
      final analysis = await AiBackendService.instance.analyzeScan(
        imageBase64: base64Encode(bytes),
        mimeType: _mimeTypeFor(_image!.path),
        scanType: _scanType,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      setState(() => _analysis = analysis);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_image == null || _analysis == null) return;
    final lang = context.read<SettingsService>().languageCode;
    final text = _analysis!.toDisplayText();
    final report = MedicalReport(
      id: const Uuid().v4(),
      title: _titleCtrl.text.trim().isEmpty
          ? '$_scanType \u2014 ${AppText.t('scan_insight_title_suffix', lang)}'
          : _titleCtrl.text.trim(),
      filePath: _image!.path,
      rawText: text,
      summary: text,
      uploadedDate: DateTime.now(),
    );
    await DatabaseService.instance.insertMedicalReport(report);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(AppText.t('scan_insight_title', lang))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            AppText.t('scan_insight_intro', lang),
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: _scanTypes.map((t) {
              final selected = t == _scanType;
              return ChoiceChip(
                label: Text(t),
                selected: selected,
                onSelected: (_) {
                  setState(() => _scanType = t);
                  if (_image != null) _analyze();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesCtrl,
            decoration: InputDecoration(
              labelText: AppText.t('scan_insight_notes', lang),
              hintText: AppText.t('scan_insight_notes_hint', lang),
              border: const OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          if (_image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(_image!, height: 200, fit: BoxFit.cover, width: double.infinity),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: Text(AppText.t('take_photo', lang)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: Text(AppText.t('from_gallery', lang)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_loading)
            Column(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 8),
                Text(AppText.t('scan_insight_analyzing', lang),
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ],
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.orange)),
            ),
          if (_analysis != null) ...[
            _ScanInsightCard(analysis: _analysis!, scanType: _scanType),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: AppText.t('title_hint', lang),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.save_outlined),
              label: Text(AppText.t('save_report', lang)),
              onPressed: _save,
            ),
          ],
        ],
      ),
    );
  }
}

/// Themed report preview — this is the "just like the sample, but honest"
/// part: a clear branded header and organized sections, without any
/// invented confidence score, risk grade, or heatmap.
class _ScanInsightCard extends StatelessWidget {
  final ScanAnalysis analysis;
  final String scanType;
  const _ScanInsightCard({required this.analysis, required this.scanType});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().languageCode;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF5B7CFA), Color(0xFF3D5AFE)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.health_and_safety_outlined, color: Colors.white, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sathi AI Scan Insight',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                      Text(
                        analysis.scanTypeGuess.isNotEmpty ? analysis.scanTypeGuess : scanType,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (analysis.imageQualityNote.isNotEmpty) ...[
                  _SectionLabel(AppText.t('scan_insight_quality', lang)),
                  Text(analysis.imageQualityNote),
                  const SizedBox(height: 12),
                ],
                _SectionLabel(AppText.t('scan_insight_overview', lang)),
                Text(analysis.overview),
                if (analysis.observations.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _SectionLabel(AppText.t('scan_insight_observations', lang)),
                  ...analysis.observations.map((o) => Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('• $o'),
                      )),
                ],
                if (analysis.suggestedSpecialist.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _SectionLabel(AppText.t('scan_insight_specialist', lang)),
                  Text(analysis.suggestedSpecialist),
                ],
                if (analysis.nextSteps.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _SectionLabel(AppText.t('scan_insight_next_steps', lang)),
                  ...analysis.nextSteps.map((s) => Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('• $s'),
                      )),
                ],
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          AppText.t('scan_insight_disclaimer', lang),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF5B7CFA)),
      ),
    );
  }
}
