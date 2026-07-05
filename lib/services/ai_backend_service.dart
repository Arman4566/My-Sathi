import 'dart:convert';
import 'package:http/http.dart' as http;
import 'ocr_service.dart';

/// This talks to YOUR OWN backend server — never directly to an LLM
/// provider's API from inside the app. Two reasons:
///  1. Security: an API key bundled inside a Flutter app can be extracted
///     from the APK/IPA in minutes. It must live server-side only.
///  2. Safety: the backend is where you enforce the medical-safety system
///     prompt (see backend/server.js in this project) so the model can't
///     be prompted around it by anything embedded in a photo or message.
///
/// See the README for a minimal Node/Express backend you can deploy
/// (Render, Railway, Fly.io, your own VPS, etc.) that proxies to Claude.
class AiBackendService {
  AiBackendService._internal();
  static final AiBackendService instance = AiBackendService._internal();

  // Replace with your deployed backend URL. Shared by auth_service.dart
  // too, so there's only one place to update after deploying.
  static const String baseUrl = 'https://my-sathi-2.onrender.com';
  static const String _baseUrl = baseUrl;

  Future<List<ParsedMedicineSuggestion>> parsePrescriptionText(
      String rawText) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/parse-prescription'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'rawText': rawText}),
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to parse prescription: ${res.statusCode}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (data['medicines'] as List?) ?? [];
    return list
        .map((e) => ParsedMedicineSuggestion.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Sends a chat message plus lightweight context (current medicine names
  /// only — not full health history) to the backend chatbot endpoint.
  /// [reportContext] optionally carries the raw text of a specific scanned
  /// report the user opened this chat from, so the assistant can discuss it.
  Future<String> sendChatMessage({
    required String message,
    required List<String> currentMedicineNames,
    String? reportContext,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': message,
        'currentMedicines': currentMedicineNames,
        'reportContext': reportContext,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception('Chat request failed: ${res.statusCode}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['reply'] as String;
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
      throw Exception('Summary request failed: ${res.statusCode}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['summary'] as String;
  }
}
