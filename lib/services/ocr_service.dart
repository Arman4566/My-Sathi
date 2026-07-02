import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'ai_backend_service.dart';

/// Represents one medicine line the AI parser believes it found
/// on the prescription. Always shown to the user for confirmation —
/// never auto-saved, since OCR + AI parsing of handwriting is fallible
/// and a wrong dosage/time is a real safety risk.
class ParsedMedicineSuggestion {
  final String name;
  final String dosage;
  final String instructions;
  final List<String> suggestedTimes;

  ParsedMedicineSuggestion({
    required this.name,
    required this.dosage,
    required this.instructions,
    required this.suggestedTimes,
  });

  factory ParsedMedicineSuggestion.fromJson(Map<String, dynamic> j) {
    return ParsedMedicineSuggestion(
      name: j['name'] ?? '',
      dosage: j['dosage'] ?? '',
      instructions: j['instructions'] ?? '',
      suggestedTimes: (j['suggestedTimes'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

class OcrService {
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Step 1: on-device OCR (free, offline, fast, works for printed text).
  /// Handwritten prescriptions are notoriously hard for OCR — see
  /// scanAndParse() below for how we compensate with an AI parsing step
  /// plus mandatory human confirmation.
  Future<String> extractRawText(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final result = await _textRecognizer.processImage(inputImage);
    return result.text;
  }

  /// Step 2: send the raw OCR text to your backend, which forwards it to
  /// an LLM to turn messy text into structured medicine entries.
  /// IMPORTANT: this always returns *suggestions*. The UI must show these
  /// to the patient/caregiver to confirm or edit before anything is saved
  /// or a reminder is scheduled — never auto-trust AI-parsed medical data.
  ///
  /// If the backend isn't reachable (e.g. not deployed yet), we fall back
  /// to a simple on-device heuristic scan instead of returning nothing —
  /// see _localFallbackParse below. It's much less accurate than the AI
  /// parser, so treat it purely as a starting point to edit, not a result
  /// to trust.
  Future<List<ParsedMedicineSuggestion>> scanAndParse(String imagePath) async {
    final rawText = await extractRawText(imagePath);
    if (rawText.trim().isEmpty) return [];

    try {
      return await AiBackendService.instance.parsePrescriptionText(rawText);
    } catch (_) {
      return _localFallbackParse(rawText);
    }
  }

  /// Very rough heuristic: picks out lines that look like they name a
  /// medicine (contain common dosage-form words like TAB/CAP/SYRUP/MG)
  /// and offers them as unconfirmed suggestions with a placeholder time.
  /// This exists only so scanning isn't a dead end without a backend —
  /// it will misfire on receipts, headers, and unrelated lines. Always
  /// let the user edit or delete what it finds.
  List<ParsedMedicineSuggestion> _localFallbackParse(String rawText) {
    final keywords = RegExp(
      r'\b(TAB|TABLET|CAP|CAPSULE|SYRUP|SYP|INJ|DROPS|MG|ML|DUO)\b',
      caseSensitive: false,
    );

    final results = <ParsedMedicineSuggestion>[];
    for (final line in rawText.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.length < 3) continue;
      if (!keywords.hasMatch(trimmed)) continue;

      results.add(ParsedMedicineSuggestion(
        name: trimmed,
        dosage: '',
        instructions: 'Detected without AI — please check carefully',
        suggestedTimes: const ['09:00'],
      ));
    }
    return results;
  }

  void dispose() {
    _textRecognizer.close();
  }
}
