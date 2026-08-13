import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/appointment_call.dart';
import 'auth_service.dart';
import 'ai_backend_service.dart';

/// Talks to the backend's AI phone-call booking feature
/// (backend/appointment_calls.js). The backend places the real call via
/// Twilio and drives the conversation with Gemini; this service just
/// starts a call and polls its status/transcript for the app to display.
///
/// Follows the same auth-header pattern as CloudSyncService.
class AppointmentCallService {
  AppointmentCallService._internal();
  static final AppointmentCallService instance = AppointmentCallService._internal();

  String get _baseUrl => AiBackendService.baseUrl;

  Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.instance.getToken();
    if (token == null) {
      throw Exception('You need to be logged in to book an appointment by phone.');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  String _extractErrorMessage(http.Response res, String fallback) {
    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['message'] as String?) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  /// Starts a call. [requestedDate] should be 'YYYY-MM-DD' and
  /// [requestedTime] a plain time string like '4:30 PM' — the AI reads
  /// these out loud, they don't need to be machine-parseable.
  Future<AppointmentCall> startCall({
    required String doctorPhone,
    required String requestedDate,
    required String requestedTime,
    String? doctorName,
    String? patientName,
    String notes = '',
  }) async {
    final headers = await _authHeaders();
    final res = await http.post(
      Uri.parse('$_baseUrl/api/appointment-calls'),
      headers: headers,
      body: jsonEncode({
        'doctorPhone': doctorPhone,
        'requestedDate': requestedDate,
        'requestedTime': requestedTime,
        'doctorName': doctorName,
        'patientName': patientName,
        'notes': notes,
      }),
    );

    if (res.statusCode == 503) {
      throw Exception(_extractErrorMessage(
          res, 'AI phone booking isn\'t set up on the backend yet.'));
    }
    if (res.statusCode != 200) {
      throw Exception(
          _extractErrorMessage(res, 'Could not start the call (${res.statusCode}).'));
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return AppointmentCall.fromJson(data['call'] as Map<String, dynamic>);
  }

  Future<AppointmentCall> getCall(String id) async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$_baseUrl/api/appointment-calls/$id'),
      headers: headers,
    );
    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res, 'Could not load call status.'));
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return AppointmentCall.fromJson(data['call'] as Map<String, dynamic>);
  }

  Future<List<AppointmentCall>> listCalls() async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$_baseUrl/api/appointment-calls'),
      headers: headers,
    );
    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res, 'Could not load call history.'));
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['calls'] as List)
        .map((c) => AppointmentCall.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<void> cancelCall(String id) async {
    final headers = await _authHeaders();
    final res = await http.delete(
      Uri.parse('$_baseUrl/api/appointment-calls/$id'),
      headers: headers,
    );
    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res, 'Could not cancel the call.'));
    }
  }
}
