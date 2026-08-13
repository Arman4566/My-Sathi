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
  /// If the backend isn't reachable (e.g. not deployed yet — see
  /// AiBackendService.baseUrl, which ships as a placeholder URL and must
  /// be set to your real deployed backend), we fall back to a simple
  /// on-device heuristic scan instead of returning nothing — see
  /// _localFallbackParse below. It's much less accurate than the AI
  /// parser, so treat it purely as a starting point to edit, not a result
  /// to trust.
  ///
  /// [rawText] should be the already-extracted OCR text (from
  /// extractRawText) — this used to re-run OCR a second time internally,
  /// doubling scan time for no benefit.
  Future<List<ParsedMedicineSuggestion>> scanAndParse(String rawText) async {
    if (rawText.trim().isEmpty) return [];

    try {
      return await AiBackendService.instance.parsePrescriptionText(rawText);
    } catch (_) {
      return _localFallbackParse(rawText);
    }
  }

  /// Rough heuristic used only when the AI backend isn't reachable.
  /// Widened beyond the original "must contain TAB/CAP/SYRUP/MG" check —
  /// that missed most real prescriptions, which is why scanning felt like
  /// it "did nothing": no keyword match meant zero suggestions and nothing
  /// to confirm or save. This now also catches:
  ///  - dose-frequency shorthand common on Indian prescriptions
  ///    (1-0-1, 1-1-1, OD/BD/TDS/QID/HS/SOS/STAT)
  ///  - a leading number/bullet followed by a capitalized word (common
  ///    prescription list formatting, e.g. "1. Paracetamol 650")
  ///  - any line containing a number immediately followed by mg/ml/mcg
  /// Always shown to the user to edit or delete — never auto-trusted.
  List<ParsedMedicineSuggestion> _localFallbackParse(String rawText) {
    final dosageForm = RegExp(
      r'\b(TAB|TABLET|CAP|CAPSULE|SYRUP|SYP|INJ|INJECTION|DROPS|OINTMENT|DUO)\b',
      caseSensitive: false,
    );
    final dosageAmount = RegExp(r'\d+\s?(MG|MCG|ML|G)\b', caseSensitive: false);
    final frequencyShorthand = RegExp(
      r'\b(\d-\d-\d|OD|BD|TDS|TID|QID|HS|SOS|STAT)\b',
      caseSensitive: false,
    );
    final numberedListItem = RegExp(r'^\s*(\d{1,2}[.).]|[-*•])\s*[A-Z]');

    // Lines that are almost certainly NOT a medicine — header/footer noise
    // commonly OCR'd off a prescription pad.
    final noise = RegExp(
      r'\b(DATE|AGE|SEX|WEIGHT|CLINIC|HOSPITAL|ADDRESS|PHONE|MOBILE|'
      r'REG\.?\s*NO|SIGNATURE|DOCTOR|DR\.?)\b',
      caseSensitive: false,
    );

    final results = <ParsedMedicineSuggestion>[];
    for (final rawLine in rawText.split('\n')) {
      final trimmed = rawLine.trim();
      if (trimmed.length < 3 || trimmed.length > 80) continue;
      if (noise.hasMatch(trimmed) && !dosageForm.hasMatch(trimmed)) continue;

      final looksLikeMedicine = dosageForm.hasMatch(trimmed) ||
          dosageAmount.hasMatch(trimmed) ||
          frequencyShorthand.hasMatch(trimmed) ||
          numberedListItem.hasMatch(trimmed);
      if (!looksLikeMedicine) continue;

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
