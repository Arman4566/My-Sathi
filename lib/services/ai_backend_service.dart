import 'dart:convert';
import 'package:http/http.dart' as http;
import 'ocr_service.dart';
import '../models/interaction_check.dart';

/// A change the assistant is proposing based on the conversation — e.g.
/// "add this medicine". The app ALWAYS shows this to the user as a
/// confirmation card and never saves it automatically; see
/// chatbot_screen.dart. Same "AI suggests, human confirms" pattern used
/// for prescription scanning.
class ChatAction {
  final String type; // 'add_medicine' | 'add_appointment' | 'find_documents'
  final Map<String, dynamic> data;

  ChatAction({required this.type, required this.data});

  factory ChatAction.fromJson(Map<String, dynamic> json) {
    return ChatAction(type: json['type'] as String, data: json);
  }
}

class ChatResponse {
  final String reply;
  final ChatAction? action;

  /// True when the assistant said it wasn't sure of its answer. The chat
  /// screen uses this to guarantee the patient is told to consult their
  /// doctor/physician, even if the model's wording didn't say so.
  final bool uncertain;
  ChatResponse({required this.reply, this.action, this.uncertain = false});
}

/// This talks to YOUR OWN backend server — never directly to an LLM
/// provider's API from inside the app. Two reasons:
///  1. Security: an API key bundled inside a Flutter app can be extracted
///     from the APK/IPA in minutes. It must live server-side only.
///  2. Safety: the backend is where you enforce the medical-safety system
///     prompt (see backend/server.js in this project) so the model can't
///     be prompted around it by anything embedded in a photo or message.
///
/// See the README for a minimal Node/Express backend you can deploy
/// (Render, Railway, Fly.io, your own VPS, etc.) that proxies to Gemini.
class AiBackendService {
  AiBackendService._internal();
  static final AiBackendService instance = AiBackendService._internal();

  // Replace with your deployed backend URL. Shared by auth_service.dart
  // and cloud_sync_service.dart too, so there's only one place to update
  // after deploying.
  static const String baseUrl = 'https://YOUR-BACKEND-URL.example.com';
  static const String _baseUrl = baseUrl;

  /// Backend error responses may include a friendlier `message` (e.g. for
  /// a Gemini overload: "The AI service is busy right now..."). Falls
  /// back to a generic message if the body isn't JSON or doesn't have one.
  String _extractErrorMessage(http.Response res, String fallback) {
    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['message'] as String?) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<List<ParsedMedicineSuggestion>> parsePrescriptionText(
      String rawText) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/parse-prescription'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'rawText': rawText}),
    );

    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(
          res, 'Failed to parse prescription: ${res.statusCode}'));
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (data['medicines'] as List?) ?? [];
    return list
        .map((e) => ParsedMedicineSuggestion.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Sends a chat message along with the patient's actual app data —
  /// medicines, appointments, recent report summaries, and profile — so
  /// the assistant can answer questions about their real situation and
  /// (only when explicitly asked, and with enough detail) propose adding
  /// a medicine or appointment via the returned [ChatResponse.action].
  /// [reportContext] optionally carries the raw text of a specific
  /// scanned report the user opened this chat from.
  /// [history] carries the recent turns of THIS conversation (oldest
  /// first) so the assistant can follow up correctly — e.g. "make that
  /// 9pm instead" only makes sense if it remembers what "that" refers to.
  /// Without this, every message was answered with zero memory of
  /// anything said earlier in the same chat.
  Future<ChatResponse> sendChatMessage({
    required String message,
    List<Map<String, String>> history = const [],
    List<Map<String, dynamic>> medicines = const [],
    List<Map<String, dynamic>> appointments = const [],
    List<Map<String, dynamic>> reports = const [],
    Map<String, dynamic>? profile,
    String? reportContext,
    String language = 'en',
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': message,
        'history': history,
        'medicines': medicines,
        'appointments': appointments,
        'reports': reports,
        'profile': profile,
        'reportContext': reportContext,
        'language': language,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception(
          _extractErrorMessage(res, 'Chat request failed: ${res.statusCode}'));
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return ChatResponse(
      reply: data['reply'] as String,
      uncertain: data['uncertain'] == true,
      action: data['action'] != null
          ? ChatAction.fromJson(data['action'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Sends the raw OCR text of an uploaded report to the backend for a
  /// plain-language AI summary AND structured numeric test values in a
  /// SINGLE call (one Gemini request, not two) — see the comment on
  /// REPORT_SUMMARY_PROMPT in server.js. The values are what power the
  /// "Lab Trends" screen: the same test tracked as a number across
  /// several dated reports can then be charted and its direction
  /// (improving/declining/stable) worked out.
  ///
  /// Throws if the summary itself can't be produced (the caller can't
  /// usefully save a report with no summary). [ReportAnalysis.values] is
  /// simply empty — never an error — for reports with no recognizable
  /// numeric results (a doctor's note, a scan description).
  Future<ReportAnalysis> analyzeReport(String rawText) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/summarize-report'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'rawText': rawText}),
    );

    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(
          res, 'Summary request failed: ${res.statusCode}'));
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final valuesList = (data['values'] as List?) ?? [];
    // Date printed on the report itself (null if the AI couldn't find
    // one). Ignored if unparseable or in the future.
    DateTime? reportDate;
    final rawDate = data['reportDate'];
    if (rawDate is String) {
      reportDate = DateTime.tryParse(rawDate.trim());
      if (reportDate != null && reportDate.isAfter(DateTime.now())) {
        reportDate = null;
      }
    }
    return ReportAnalysis(
      summary: data['summary'] as String? ?? '',
      values: valuesList.cast<Map<String, dynamic>>(),
      reportDate: reportDate,
    );
  }

  /// "Sathi AI Scan Insight" — sends a photo of an X-ray/ultrasound/similar
  /// scan to the backend for a plain-language description. See
  /// SCAN_ANALYSIS_PROMPT in server.js for exactly why this deliberately
  /// never returns a confidence percentage, a risk grade, or a diagnosis —
  /// short version: Gemini isn't a validated diagnostic imaging model, and
  /// faking that precision would be actively misleading.
  Future<ScanAnalysis> analyzeScan({
    required String imageBase64,
    required String mimeType,
    String? scanType,
    String? notes,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/analyze-scan'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'imageBase64': imageBase64,
        'mimeType': mimeType,
        'scanType': scanType,
        'notes': notes,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception(
          _extractErrorMessage(res, 'Scan analysis failed: ${res.statusCode}'));
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return ScanAnalysis.fromJson(data['analysis'] as Map<String, dynamic>);
  }

  /// "AI Safety & Interaction Guard" — checks one or more medicines the
  /// patient is about to add against their current active medicines for
  /// drug-drug interactions, plus general food/timing precautions for
  /// each new medicine. See INTERACTION_CHECK_PROMPT in server.js for
  /// exactly how conservative the model is instructed to be (an empty
  /// result is expected and fine — it should never pad the list to seem
  /// thorough).
  ///
  /// This is informational only, same "AI suggests, human confirms"
  /// pattern as the rest of the app: the caller decides what to do with
  /// the result (e.g. show a warning dialog) and never has a save
  /// blocked by this call failing — see the callers in
  /// scan_prescription_screen.dart and medicine_list_screen.dart, which
  /// treat a failed check as "no warning available" rather than an
  /// error the user has to deal with.
  Future<InteractionCheckResult> checkInteractions({
    required List<Map<String, dynamic>> newMedicines,
    required List<Map<String, dynamic>> currentMedicines,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/check-interactions'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'newMedicines': newMedicines,
        'currentMedicines': currentMedicines,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(
          res, 'Interaction check failed: ${res.statusCode}'));
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return InteractionCheckResult.fromJson(data);
  }

  /// "Emergency Medical Card" — sends the patient's blood group,
  /// allergies, chronic conditions, and current medicines to the backend,
  /// which returns a short AI-written plain-language recap PLUS a ready
  /// -to-share PDF built from that same data. See
  /// EMERGENCY_CARD_PROMPT/buildEmergencyCardPdf in the backend for why
  /// only the recap sentence is AI-generated — every field that actually
  /// matters in an emergency (allergies, medicines, blood group) is the
  /// patient's own data, placed on the PDF unmodified, never left to the
  /// model to reconstruct.
  Future<EmergencyCardResult> generateEmergencyCard({
    required String patientName,
    int? age,
    String? gender,
    String? bloodGroup,
    String? allergies,
    String? chronicConditions,
    required List<Map<String, dynamic>> medicines,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/emergency-card'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'patientName': patientName,
        'age': age,
        'gender': gender,
        'bloodGroup': bloodGroup,
        'allergies': allergies,
        'chronicConditions': chronicConditions,
        'medicines': medicines,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(
          res, 'Could not generate the emergency card: ${res.statusCode}'));
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return EmergencyCardResult(
      summary: data['summary'] as String? ?? '',
      pdfBytes: base64Decode(data['pdfBase64'] as String),
    );
  }
}

/// Result of POST /api/emergency-card — see
/// AiBackendService.generateEmergencyCard.
class EmergencyCardResult {
  final String summary;
  final List<int> pdfBytes;
  EmergencyCardResult({required this.summary, required this.pdfBytes});
}

/// Result of the combined /api/summarize-report call: a plain-language
/// summary plus any structured numeric test values found in the same
/// pass — see AiBackendService.analyzeReport.
class ReportAnalysis {
  final String summary;
  final List<Map<String, dynamic>> values;

  /// Date printed on the report (not upload time); null if not found.
  final DateTime? reportDate;
  ReportAnalysis(
      {required this.summary, required this.values, this.reportDate});
}

/// Result of "Sathi AI Scan Insight" (see analyzeScan above). Intentionally
/// has NO confidence score and NO risk level field — see the long comment
/// on SCAN_ANALYSIS_PROMPT in server.js for why those are deliberately
/// left out rather than fabricated.
class ScanAnalysis {
  final String scanTypeGuess;
  final String imageQualityNote;
  final String overview;
  final List<String> observations;
  final String suggestedSpecialist;
  final List<String> nextSteps;

  ScanAnalysis({
    required this.scanTypeGuess,
    required this.imageQualityNote,
    required this.overview,
    required this.observations,
    required this.suggestedSpecialist,
    required this.nextSteps,
  });

  factory ScanAnalysis.fromJson(Map<String, dynamic> j) {
    return ScanAnalysis(
      scanTypeGuess: j['scanTypeGuess'] as String? ?? '',
      imageQualityNote: j['imageQualityNote'] as String? ?? '',
      overview: j['overview'] as String? ?? '',
      observations:
          (j['observations'] as List?)?.map((e) => e.toString()).toList() ?? [],
      suggestedSpecialist: j['suggestedSpecialist'] as String? ?? '',
      nextSteps: (j['nextSteps'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  /// Formatted for saving into MedicalReport.summary / .rawText so it
  /// reads well in the existing ReportDetailScreen (which just renders
  /// these as plain Text — no special "scan report" UI needed there).
  String toDisplayText() {
    final b = StringBuffer();
    b.writeln('🩺 Sathi AI Scan Insight');
    if (scanTypeGuess.isNotEmpty) b.writeln('Scan type: $scanTypeGuess');
    b.writeln();
    b.writeln(overview);
    if (imageQualityNote.isNotEmpty) {
      b.writeln();
      b.writeln('Image quality note: $imageQualityNote');
    }
    if (observations.isNotEmpty) {
      b.writeln();
      b.writeln('What we noticed:');
      for (final o in observations) {
        b.writeln('• $o');
      }
    }
    if (suggestedSpecialist.isNotEmpty) {
      b.writeln();
      b.writeln('A general starting point if you want to follow up: $suggestedSpecialist');
    }
    if (nextSteps.isNotEmpty) {
      b.writeln();
      b.writeln('Suggested next steps:');
      for (final s in nextSteps) {
        b.writeln('• $s');
      }
    }
    b.writeln();
    b.writeln(
        '⚠️ This is an AI-assisted description, not a diagnosis. Please share the actual scan with a qualified doctor or radiologist for proper evaluation.');
    return b.toString().trim();
  }
}
