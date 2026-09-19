import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/xray_report.dart';
import 'auth_service.dart';
import 'ai_backend_service.dart';

/// Talks to the backend's chest X-ray "AI Diagnostic Report" feature
/// (backend/xray_reports.js), which forwards the image to the separate
/// xray_ai_service (a real pretrained model + real Grad-CAM — see that
/// service's README) and returns a themed PDF built from the real
/// response, saved server-side so it can be re-downloaded later.
///
/// Follows the same auth-header pattern as AppointmentCallService.
class XrayReportService {
  XrayReportService._internal();
  static final XrayReportService instance = XrayReportService._internal();

  String get _baseUrl => AiBackendService.baseUrl;

  Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.instance.getToken();
    if (token == null) {
      throw Exception('You need to be logged in to generate an AI diagnostic report.');
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

  /// Uploads a chest X-ray photo and returns the generated report
  /// (metadata + PDF bytes, ready to show/download immediately). Can
  /// take several seconds — real CPU model inference + Grad-CAM, not an
  /// instant call.
  Future<XrayAnalysisResult> analyze({
    required List<int> imageBytes,
    required String mimeType,
    String? patientName,
    String? patientId,
  }) async {
    final headers = await _authHeaders();
    final res = await http
        .post(
          Uri.parse('$_baseUrl/api/xray-reports/analyze'),
          headers: headers,
          body: jsonEncode({
            'imageBase64': base64Encode(imageBytes),
            'mimeType': mimeType,
            'patientName': patientName,
            'patientId': patientId,
          }),
        )
        .timeout(const Duration(seconds: 90));

    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res, 'Could not generate the report (${res.statusCode}).'));
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final reportJson = data['report'] as Map<String, dynamic>;
    return XrayAnalysisResult(
      report: XrayReport.fromJson(reportJson),
      warnings: ((reportJson['warnings'] as List?) ?? []).map((e) => e.toString()).toList(),
      pdfBytes: base64Decode(data['pdfBase64'] as String),
    );
  }

  Future<List<XrayReport>> listReports() async {
    final headers = await _authHeaders();
    final res = await http.get(Uri.parse('$_baseUrl/api/xray-reports'), headers: headers);
    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res, 'Could not load your reports (${res.statusCode}).'));
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['reports'] as List).map((j) => XrayReport.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<List<int>> downloadPdf(String id) async {
    final headers = await _authHeaders();
    final res = await http.get(Uri.parse('$_baseUrl/api/xray-reports/$id/pdf'), headers: headers);
    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res, 'Could not download this report (${res.statusCode}).'));
    }
    return res.bodyBytes;
  }

  Future<void> deleteReport(String id) async {
    final headers = await _authHeaders();
    await http.delete(Uri.parse('$_baseUrl/api/xray-reports/$id'), headers: headers);
  }
}
