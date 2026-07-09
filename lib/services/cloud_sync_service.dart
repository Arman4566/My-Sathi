import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/medicine.dart';
import '../models/appointment.dart';
import '../models/prescription.dart';
import '../models/medical_report.dart';
import '../models/health_record.dart';
import 'auth_service.dart';
import 'ai_backend_service.dart';
import 'database_service.dart';

/// Keeps local SQLite data in sync with the cloud backend, so logging in
/// on a different phone brings your medicines, appointments, reports, and
/// health log with it — not just your account.
///
/// Two directions:
/// - push*: called after every local write (insert/update/delete). Fire
///   and forget — wrapped so a network failure or logged-out state never
///   throws into the caller or blocks the UI. If the push fails, the
///   local write still stands; it'll sync next time a push succeeds
///   after a change, or you can extend this with a proper retry/outbox
///   queue for stronger guarantees.
/// - pullAllAndMerge: called once after login/signup and once at app
///   startup if already logged in. Downloads everything from the cloud
///   and upserts it into local SQLite by id, so a fresh install/new
///   device ends up with the same data.
///
/// NOTE: this syncs the DATA (text/dates/numbers). Photo/file fields
/// (imagePath, filePath, photoPath) are NOT uploaded anywhere — they
/// stay as local device paths and won't resolve on a different phone.
/// See schema.sql for why, and what real photo sync would need.
class CloudSyncService {
  CloudSyncService._internal();
  static final CloudSyncService instance = CloudSyncService._internal();

  String get _baseUrl => AiBackendService.baseUrl;

  Future<Map<String, String>?> _authHeaders() async {
    final token = await AuthService.instance.getToken();
    if (token == null) return null; // not logged in — nothing to sync
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ---------- Push (local -> cloud) ----------

  Future<void> pushMedicine(Medicine m) async {
    await _pushSafely('medicines', {
      'id': m.id,
      'name': m.name,
      'dosage': m.dosage,
      'instructions': m.instructions,
      'times': m.times.join(','),
      'startDate': m.startDate.toIso8601String(),
      'endDate': m.endDate?.toIso8601String(),
      'frequency': m.frequency.name,
      'customDays': m.customDays.join(','),
      'active': m.active,
      'photoPath': m.photoPath,
      'prescribedBy': m.prescribedBy,
    });
  }

  Future<void> deleteMedicine(String id) => _deleteSafely('medicines', id);

  Future<void> pushAppointment(Appointment a) async {
    await _pushSafely('appointments', {
      'id': a.id,
      'doctorName': a.doctorName,
      'location': a.location,
      'dateTime': a.dateTime.toIso8601String(),
      'notes': a.notes,
      'reminderSet': a.reminderSet,
    });
  }

  Future<void> deleteAppointment(String id) => _deleteSafely('appointments', id);

  Future<void> pushPrescription(Prescription p) async {
    await _pushSafely('prescriptions', {
      'id': p.id,
      'imagePath': p.imagePath,
      'rawText': p.rawText,
      'doctorName': p.doctorName,
      'dateAdded': p.dateAdded.toIso8601String(),
      'notes': p.notes,
    });
  }

  Future<void> deletePrescription(String id) => _deleteSafely('prescriptions', id);

  Future<void> pushMedicalReport(MedicalReport r) async {
    await _pushSafely('medical-reports', {
      'id': r.id,
      'title': r.title,
      'filePath': r.filePath,
      'rawText': r.rawText,
      'summary': r.summary,
      'uploadedDate': r.uploadedDate.toIso8601String(),
    });
  }

  Future<void> deleteMedicalReport(String id) => _deleteSafely('medical-reports', id);

  Future<void> pushHealthRecord(HealthRecord r) async {
    await _pushSafely('health-records', {
      'id': r.id,
      'date': r.date.toIso8601String(),
      'weightKg': r.weightKg,
      'bloodPressure': r.bloodPressure,
      'sugarLevel': r.sugarLevel,
      'notes': r.notes,
    });
  }

  Future<void> deleteHealthRecord(String id) => _deleteSafely('health-records', id);

  Future<void> _pushSafely(String endpoint, Map<String, dynamic> body) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return;
      await http
          .post(Uri.parse('$_baseUrl/api/$endpoint'),
              headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // Offline, backend not deployed yet, etc. — the local write already
      // succeeded, so we just skip cloud sync silently this time rather
      // than disrupt the user's flow.
    }
  }

  Future<void> _deleteSafely(String endpoint, String id) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return;
      await http
          .delete(Uri.parse('$_baseUrl/api/$endpoint/$id'), headers: headers)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // Same reasoning as _pushSafely.
    }
  }

  // ---------- Pull (cloud -> local), for logging in on a new device ----------

  Future<void> pullAllAndMerge() async {
    final headers = await _authHeaders();
    if (headers == null) return;

    await Future.wait([
      _pullMedicines(headers),
      _pullAppointments(headers),
      _pullPrescriptions(headers),
      _pullMedicalReports(headers),
      _pullHealthRecords(headers),
    ]);
  }

  Future<void> _pullMedicines(Map<String, String> headers) async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/api/medicines'), headers: headers)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return;
      final list = (jsonDecode(res.body)['medicines'] as List);
      for (final j in list) {
        final medicine = Medicine(
          id: j['id'],
          name: j['name'] ?? '',
          dosage: j['dosage'] ?? '',
          instructions: j['instructions'] ?? '',
          times: (j['times'] as String? ?? '').isEmpty
              ? []
              : (j['times'] as String).split(','),
          startDate: DateTime.tryParse(j['startDate'] ?? '') ?? DateTime.now(),
          endDate: j['endDate'] != null ? DateTime.tryParse(j['endDate']) : null,
          frequency: MedicineFrequency.values.firstWhere(
              (f) => f.name == (j['frequency'] ?? 'daily'),
              orElse: () => MedicineFrequency.daily),
          customDays: (j['customDays'] as String? ?? '').isEmpty
              ? []
              : (j['customDays'] as String).split(',').map(int.parse).toList(),
          active: j['active'] ?? true,
          photoPath: j['photoPath'],
          prescribedBy: j['prescribedBy'],
        );
        await DatabaseService.instance.insertMedicine(medicine, sync: false);
      }
    } catch (_) {}
  }

  Future<void> _pullAppointments(Map<String, String> headers) async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/api/appointments'), headers: headers)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return;
      final list = (jsonDecode(res.body)['appointments'] as List);
      for (final j in list) {
        final appt = Appointment(
          id: j['id'],
          doctorName: j['doctorName'] ?? '',
          location: j['location'] ?? '',
          dateTime: DateTime.tryParse(j['dateTime'] ?? '') ?? DateTime.now(),
          notes: j['notes'] ?? '',
          reminderSet: j['reminderSet'] ?? true,
        );
        await DatabaseService.instance.insertAppointment(appt, sync: false);
      }
    } catch (_) {}
  }

  Future<void> _pullPrescriptions(Map<String, String> headers) async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/api/prescriptions'), headers: headers)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return;
      final list = (jsonDecode(res.body)['prescriptions'] as List);
      for (final j in list) {
        final p = Prescription(
          id: j['id'],
          imagePath: j['imagePath'] ?? '',
          rawText: j['rawText'] ?? '',
          doctorName: j['doctorName'] ?? '',
          dateAdded: DateTime.tryParse(j['dateAdded'] ?? '') ?? DateTime.now(),
          notes: j['notes'] ?? '',
        );
        await DatabaseService.instance.insertPrescription(p, sync: false);
      }
    } catch (_) {}
  }

  Future<void> _pullMedicalReports(Map<String, String> headers) async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/api/medical-reports'), headers: headers)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return;
      final list = (jsonDecode(res.body)['reports'] as List);
      for (final j in list) {
        final r = MedicalReport(
          id: j['id'],
          title: j['title'] ?? '',
          filePath: j['filePath'] ?? '',
          rawText: j['rawText'] ?? '',
          summary: j['summary'] ?? '',
          uploadedDate: DateTime.tryParse(j['uploadedDate'] ?? '') ?? DateTime.now(),
        );
        await DatabaseService.instance.insertMedicalReport(r, sync: false);
      }
    } catch (_) {}
  }

  Future<void> _pullHealthRecords(Map<String, String> headers) async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/api/health-records'), headers: headers)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return;
      final list = (jsonDecode(res.body)['records'] as List);
      for (final j in list) {
        final r = HealthRecord(
          id: j['id'],
          date: DateTime.tryParse(j['date'] ?? '') ?? DateTime.now(),
          weightKg: (j['weightKg'] as num?)?.toDouble(),
          bloodPressure: j['bloodPressure'],
          sugarLevel: (j['sugarLevel'] as num?)?.toDouble(),
          notes: j['notes'] ?? '',
        );
        await DatabaseService.instance.insertHealthRecord(r, sync: false);
      }
    } catch (_) {}
  }
}
