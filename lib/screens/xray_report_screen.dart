import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/xray_report.dart';
import '../services/xray_report_service.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';

/// "Sathi AI Diagnostic Report" — the real-pretrained-model chest X-ray
/// feature. Unlike ScanAnalysisScreen (Gemini describing what it sees in
/// plain language), this calls xray_ai_service via
/// backend/xray_reports.js to get genuine per-condition confidence
/// scores and a genuine Grad-CAM heatmap, packaged into a themed,
/// downloadable PDF. See xray_ai_service/README.md for exactly what the
/// underlying model is and its real limitations.
class XrayReportScreen extends StatefulWidget {
  const XrayReportScreen({super.key});
  @override
  State<XrayReportScreen> createState() => _XrayReportScreenState();
}

class _XrayReportScreenState extends State<XrayReportScreen> {
  final _picker = ImagePicker();

  File? _image;
  bool _loading = false;
  String? _error;
  XrayAnalysisResult? _result;

  List<XrayReport> _pastReports = [];
  bool _loadingPast = true;

  @override
  void initState() {
    super.initState();
    _loadPastReports();
  }

  Future<void> _loadPastReports() async {
    try {
      final reports = await XrayReportService.instance.listReports();
      if (mounted) setState(() { _pastReports = reports; _loadingPast = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingPast = false);
    }
  }

  String _mimeTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 90);
    if (picked == null) return;
    setState(() {
      _image = File(picked.path);
      _result = null;
      _error = null;
    });
  }

  Future<void> _generate() async {
    if (_image == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await AuthService.instance.getCurrentProfile();
      final bytes = await _image!.readAsBytes();
      final result = await XrayReportService.instance.analyze(
        imageBytes: bytes,
        mimeType: _mimeTypeFor(_image!.path),
        patientName: profile?.name,
      );
      setState(() => _result = result);
      _loadPastReports();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<File> _writePdfToTemp(List<int> bytes, String title) async {
    final dir = await getTemporaryDirectory();
    final safeName = title.replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '').trim();
    final file = File('${dir.path}/${safeName.isEmpty ? 'sathi-xray-report' : safeName}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _openPdf(List<int> bytes, String title) async {
    final file = await _writePdfToTemp(bytes, title);
    await OpenFile.open(file.path);
  }

  Future<void> _sharePdf(List<int> bytes, String title) async {
    final file = await _writePdfToTemp(bytes, title);
    // Share.shareXFiles is the long-stable share_plus API (available
    // since early 3.x releases through the 7.x/8.x line this app is
    // pinned to) — deliberately not using the newer SharePlus.instance
    // unified API added in share_plus 10+, since pubspec.yaml pins
    // ^7.2.2 and that newer API isn't available on this version.
    await Share.shareXFiles([XFile(file.path)], text: title);
  }

  Future<void> _openPastReport(XrayReport report) async {
    try {
      final bytes = await XrayReportService.instance.downloadPdf(report.id);
      await _openPdf(bytes, report.title);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(AppText.t('xray_report_title', lang))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(AppText.t('xray_report_intro', lang), style: TextStyle(color: Colors.grey[600], fontSize: 13)),
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
          if (_image != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _loading
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.health_and_safety_outlined),
                label: Text(_loading ? '' : AppText.t('xray_report_generate', lang)),
                onPressed: _loading ? null : _generate,
              ),
            ),
          ],
          if (_loading)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(AppText.t('xray_report_analyzing', lang),
                  style: TextStyle(color: Colors.grey[600], fontSize: 13), textAlign: TextAlign.center),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.orange)),
            ),
          if (_result != null) ...[
            const SizedBox(height: 16),
            _ResultCard(result: _result!, lang: lang),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(AppText.t('xray_report_download', lang)),
                    onPressed: () => _openPdf(_result!.pdfBytes, _result!.report.title),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.share_outlined),
                    label: Text(AppText.t('xray_report_share', lang)),
                    onPressed: () => _sharePdf(_result!.pdfBytes, _result!.report.title),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 28),
          Text(AppText.t('xray_report_past_reports', lang),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          if (_loadingPast)
            const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
          else if (_pastReports.isEmpty)
            Text(AppText.t('xray_report_no_reports', lang), style: TextStyle(color: Colors.grey[500]))
          else
            ..._pastReports.map((r) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFF3D5AFE)),
                    title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${r.primaryFinding} \u2014 ${(r.confidence * 100).toStringAsFixed(1)}% (${r.confidenceBand})'),
                    onTap: () => _openPastReport(r),
                  ),
                )),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final XrayAnalysisResult result;
  final String lang;
  const _ResultCard({required this.result, required this.lang});

  @override
  Widget build(BuildContext context) {
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
                colors: [Color(0xFF3D5AFE), Color(0xFF1A237E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.health_and_safety_outlined, color: Colors.white, size: 28),
                const SizedBox(width: 10),
                const Text('Sathi AI Diagnostic Report',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppText.t('xray_report_primary_finding', lang),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF3D5AFE))),
                Text(result.report.primaryFinding, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 10),
                Text(AppText.t('xray_report_confidence', lang),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF3D5AFE))),
                Text('${(result.report.confidence * 100).toStringAsFixed(1)}% (${result.report.confidenceBand})',
                    style: const TextStyle(fontSize: 16)),
                if (result.warnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: result.warnings
                          .map((w) => Text(w, style: const TextStyle(fontSize: 12)))
                          .toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Full findings table, image-quality metrics, and the Grad-CAM heatmap are in the PDF below.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
