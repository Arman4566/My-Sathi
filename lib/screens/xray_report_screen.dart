import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/xray_report.dart';
import '../services/xray_report_service.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/local_file_storage_service.dart';
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
    // Local-first: instant, and works offline — this is what makes past
    // reports still show up after an app restart or re-login on this
    // device (see LocalFileStorageService / DatabaseService's
    // xray_reports_local table).
    final local = await DatabaseService.instance.getXrayReportsLocal();
    if (mounted) setState(() { _pastReports = local; _loadingPast = false; });

    // Then reconcile with the backend in the background: pick up any
    // reports generated on a different device that aren't cached on this
    // one yet (shown with no local copy until opened, which caches them
    // here for next time — see _openPastReport).
    try {
      final remote = await XrayReportService.instance.listReports();
      final localIds = local.map((r) => r.id).toSet();
      final onlyRemote = remote.where((r) => !localIds.contains(r.id)).toList();
      if (onlyRemote.isNotEmpty && mounted) {
        setState(() {
          _pastReports = [..._pastReports, ...onlyRemote]
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        });
      }
    } catch (_) {
      // Offline or backend unreachable — the local list above still shows.
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

      // Save the PDF and the source photo to this device's persistent
      // storage right away — this (plus the xray_reports_local DB row)
      // is what makes the report still show up, with its PDF openable,
      // after an app restart or re-login on this device.
      final localPdfPath = await LocalFileStorageService.instance.saveBytes(
        result.pdfBytes,
        subfolder: 'xray_reports',
        filename: '${result.report.id}.pdf',
      );
      String? localPhotoPath;
      try {
        final ext = _image!.path.contains('.') ? _image!.path.split('.').last : 'jpg';
        localPhotoPath = await LocalFileStorageService.instance.savePickedFile(
          _image!,
          subfolder: 'xray_photos',
          filename: '${result.report.id}.$ext',
        );
      } catch (_) {
        // Non-fatal — the PDF itself is the important artifact; losing
        // the source photo copy shouldn't block anything.
      }

      final reportWithLocal = result.report.copyWith(
        localPdfPath: localPdfPath,
        localPhotoPath: localPhotoPath,
      );
      await DatabaseService.instance.saveXrayReportLocal(reportWithLocal);

      setState(() => _result = XrayAnalysisResult(
            report: reportWithLocal,
            warnings: result.warnings,
            pdfBytes: result.pdfBytes,
          ));
      _loadPastReports();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _openPdfFile(String path) async {
    await OpenFile.open(path);
  }

  Future<void> _sharePdfFile(String path, String title) async {
    // Share.shareXFiles is the long-stable share_plus API (available
    // since early 3.x releases through the 7.x/8.x line this app is
    // pinned to) — deliberately not using the newer SharePlus.instance
    // unified API added in share_plus 10+, since pubspec.yaml pins
    // ^7.2.2 and that newer API isn't available on this version.
    await Share.shareXFiles([XFile(path)], text: title);
  }

  Future<void> _openPastReport(XrayReport report) async {
    try {
      String pdfPath;
      if (await LocalFileStorageService.instance.exists(report.localPdfPath)) {
        pdfPath = report.localPdfPath!;
      } else {
        // Not cached on this device yet (e.g. generated elsewhere, or
        // this is a fresh login) — download once, then cache it locally
        // so the next open (and the next app restart) doesn't need the
        // network at all.
        final bytes = await XrayReportService.instance.downloadPdf(report.id);
        pdfPath = await LocalFileStorageService.instance
            .saveBytes(bytes, subfolder: 'xray_reports', filename: '${report.id}.pdf');
        final updated = report.copyWith(localPdfPath: pdfPath);
        await DatabaseService.instance.saveXrayReportLocal(updated);
        _loadPastReports();
      }
      await _openPdfFile(pdfPath);
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
                    onPressed: () => _openPdfFile(_result!.report.localPdfPath!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.share_outlined),
                    label: Text(AppText.t('xray_report_share', lang)),
                    onPressed: () =>
                        _sharePdfFile(_result!.report.localPdfPath!, _result!.report.title),
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
