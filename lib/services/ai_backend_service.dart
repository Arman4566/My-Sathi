import 'dart:convert';
import 'package:http/http.dart' as http;
import 'ocr_service.dart';

/// A change the assistant is proposing based on the conversation — e.g.
/// "add this medicine". The app ALWAYS shows this to the user as a
/// confirmation card and never saves it automatically; see
/// chatbot_screen.dart. Same "AI suggests, human confirms" pattern used
/// for prescription scanning.
class ChatAction {
  final String type; // 'add_medicine' | 'add_appointment'
  final Map<String, dynamic> data;

  ChatAction({required this.type, required this.data});

  factory ChatAction.fromJson(Map<String, dynamic> json) {
    return ChatAction(type: json['type'] as String, data: json);
  }
}

class ChatResponse {
  final String reply;
  final ChatAction? action;
  ChatResponse({required this.reply, this.action});
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
  static const String baseUrl = 'https://my-sathi3.onrender.com';
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
      action: data['action'] != null
          ? ChatAction.fromJson(data['action'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Sends the raw OCR text of an uploaded report to the backend for a
  /// plain-language AI summary. See REPORT_SUMMARY_PROMPT in server.js
  /// for the exact rules the summary follows (no diagnosing, flags
  /// abnormal values without interpreting them).
  Future<String> summarizeReport(String rawText) async {
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
    return data['summary'] as String;
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
