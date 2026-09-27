import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import '../models/user_profile.dart';
import '../services/ai_backend_service.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/local_file_storage_service.dart';

/// "Emergency Medical Card" — a one-tap, printable/shareable summary of
/// the patient's blood group, allergies, chronic conditions, and current
/// medicines, meant to be handed to a family member or an ER doctor in
/// a hurry. See AiBackendService.generateEmergencyCard and
/// backend/emergency_card_pdf.js for why only the closing recap sentence
/// is AI-written — every safety-critical field is the patient's own
/// data, unmodified.
class EmergencyCardScreen extends StatefulWidget {
  const EmergencyCardScreen({super.key});
  @override
  State<EmergencyCardScreen> createState() => _EmergencyCardScreenState();
}

class _EmergencyCardScreenState extends State<EmergencyCardScreen> {
  bool _loading = false;
  String? _error;
  String? _summary;
  String? _localPdfPath;

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final UserProfile? profile = await AuthService.instance.getCurrentProfile();
      if (profile == null) throw Exception('You need to be logged in.');

      final medicines = await DatabaseService.instance.getActiveMedicines();
      final medicinePayload = medicines
          .map((m) => {
                'name': m.name,
                'dosage': m.dosage,
                'times': m.times,
              })
          .toList();

      final result = await AiBackendService.instance.generateEmergencyCard(
        patientName: profile.name,
        age: profile.age,
        gender: profile.gender,
        bloodGroup: profile.bloodGroup,
        allergies: profile.allergies,
        chronicConditions: profile.chronicConditions,
        medicines: medicinePayload,
      );

      // Persist the PDF so it can be reopened/shared without regenerating
      // — same pattern as the X-ray AI Diagnostic Report (see
      // LocalFileStorageService's doc comment for why the temp/cache
      // directory isn't good enough for this).
      final localPath = await LocalFileStorageService.instance.saveBytes(
        result.pdfBytes,
        subfolder: 'emergency_card',
        filename: '${profile.id}.pdf',
      );

      setState(() {
        _summary = result.summary;
        _localPdfPath = localPath;
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _openPdf() async {
    if (_localPdfPath == null) return;
    await OpenFile.open(_localPdfPath!);
  }

  Future<void> _sharePdf() async {
    if (_localPdfPath == null) return;
    await Share.shareXFiles([XFile(_localPdfPath!)],
        text: 'Emergency Medical Card');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Medical Card')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.medical_information_outlined,
                      color: Color(0xFF5B7CFA), size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Generates a compact PDF with your blood group, '
                      'allergies, chronic conditions, and current '
                      'medicines — ready to share with a family member '
                      'or show a doctor in an emergency.',
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],
            ElevatedButton.icon(
              onPressed: _loading ? null : _generate,
              icon: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome),
              label: Text(_localPdfPath == null
                  ? 'Generate Emergency Card'
                  : 'Regenerate (data changed?)'),
            ),
            if (_summary != null && _summary!.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('Quick summary',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Text(_summary!),
              ),
            ],
            if (_localPdfPath != null) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Open PDF'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _sharePdf,
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Tip: fill in blood group, allergies, and chronic conditions '
              'on your Profile screen first — anything left blank shows '
              'as "None recorded" on the card.',
              style: TextStyle(
                  color: Theme.of(context).hintColor, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
