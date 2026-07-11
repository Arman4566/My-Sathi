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
  static const String baseUrl = 'https://my-sathi-2.onrender.com';
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
  Future<ChatResponse> sendChatMessage({
    required String message,
    List<Map<String, dynamic>> medicines = const [],
    List<Map<String, dynamic>> appointments = const [],
    List<Map<String, dynamic>> reports = const [],
    Map<String, dynamic>? profile,
    String? reportContext,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': message,
        'medicines': medicines,
        'appointments': appointments,
        'reports': reports,
        'profile': profile,
        'reportContext': reportContext,
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
}
