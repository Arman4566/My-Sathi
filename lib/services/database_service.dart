import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/medicine.dart';
import '../models/prescription.dart';
import '../models/appointment.dart';
import '../models/user_profile.dart';
import '../models/health_record.dart';
import '../models/medical_report.dart';
import 'cloud_sync_service.dart';

/// Single source of truth for all local persistence.
/// Everything lives on-device (SQLite) so patient health data
/// never leaves the phone unless the user explicitly exports it
/// or sends something to the chatbot.
class DatabaseService {
  DatabaseService._internal();
  static final DatabaseService instance = DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'patient_care.db');

    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE medicines (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            dosage TEXT,
            instructions TEXT,
            times TEXT,
            startDate TEXT,
            endDate TEXT,
            prescriptionId TEXT,
            active INTEGER,
            frequency TEXT,
            customDays TEXT,
            photoPath TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE prescriptions (
            id TEXT PRIMARY KEY,
            imagePath TEXT,
            rawText TEXT,
            doctorName TEXT,
            dateAdded TEXT,
            notes TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE appointments (
            id TEXT PRIMARY KEY,
            doctorName TEXT,
            location TEXT,
            dateTime TEXT,
            notes TEXT,
            reminderSet INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE profiles (
            id TEXT PRIMARY KEY,
            name TEXT,
            email TEXT UNIQUE,
            passwordHash TEXT,
            age INTEGER,
            weightKg REAL,
            heightCm REAL,
            gender TEXT,
            photoPath TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE health_records (
            id TEXT PRIMARY KEY,
            date TEXT,
            weightKg REAL,
            bloodPressure TEXT,
            sugarLevel REAL,
            notes TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE medical_reports (
            id TEXT PRIMARY KEY,
            title TEXT,
            filePath TEXT,
            rawText TEXT,
            summary TEXT,
            uploadedDate TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Upgrading from the original schema: add the new
          // frequency/customDays columns and the new tables.
          await db.execute(
              "ALTER TABLE medicines ADD COLUMN frequency TEXT DEFAULT 'daily'");
          await db.execute(
              "ALTER TABLE medicines ADD COLUMN customDays TEXT DEFAULT ''");
          await db.execute('''
            CREATE TABLE IF NOT EXISTS profiles (
              id TEXT PRIMARY KEY,
              name TEXT,
              email TEXT UNIQUE,
              passwordHash TEXT,
              age INTEGER,
              weightKg REAL,
              heightCm REAL,
              gender TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS health_records (
              id TEXT PRIMARY KEY,
              date TEXT,
              weightKg REAL,
              bloodPressure TEXT,
              sugarLevel REAL,
              notes TEXT
            )
          ''');
        }
        if (oldVersion < 3) {
          // Photo support for medicines and profiles, plus the new
          // medical reports table for the "upload a report" feature.
          await db.execute('ALTER TABLE medicines ADD COLUMN photoPath TEXT');
          await db.execute('ALTER TABLE profiles ADD COLUMN photoPath TEXT');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS medical_reports (
              id TEXT PRIMARY KEY,
              title TEXT,
              filePath TEXT,
              rawText TEXT,
              summary TEXT,
              uploadedDate TEXT
            )
          ''');
        }
      },
    );
  }

  // ---------- Medicines ----------
  /// [sync] pushes this write to the cloud backend (fire-and-forget).
  /// Set to false only when writing data that just came FROM the cloud
  /// (see CloudSyncService.pullAllAndMerge), so pulling doesn't
  /// immediately push the same data straight back.
  Future<void> insertMedicine(Medicine m, {bool sync = true}) async {
    final db = await database;
    await db.insert('medicines', m.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    if (sync) unawaited(CloudSyncService.instance.pushMedicine(m));
  }

  Future<void> updateMedicine(Medicine m, {bool sync = true}) async {
    final db = await database;
    await db.update('medicines', m.toMap(), where: 'id = ?', whereArgs: [m.id]);
    if (sync) unawaited(CloudSyncService.instance.pushMedicine(m));
  }

  /// Returns active medicines, having first auto-deactivated any whose
  /// end date has passed. This is how "custom duration then auto-remove"
  /// is enforced — checked every time the list is read.
  Future<List<Medicine>> getActiveMedicines() async {
    await _deactivateExpiredMedicines();
    final db = await database;
    final rows = await db.query('medicines', where: 'active = 1');
    return rows.map((r) => Medicine.fromMap(r)).toList();
  }

  Future<void> _deactivateExpiredMedicines() async {
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();
    final expiring = await db.query(
      'medicines',
      where: 'active = 1 AND endDate IS NOT NULL AND endDate < ?',
      whereArgs: [nowIso],
    );
    await db.update(
      'medicines',
      {'active': 0},
      where: 'active = 1 AND endDate IS NOT NULL AND endDate < ?',
      whereArgs: [nowIso],
    );
    // Reflect the auto-expiry in the cloud too, so it doesn't come back
    // as "active" when pulled on another device.
    for (final row in expiring) {
      final medicine = Medicine.fromMap(row).copyWith(active: false);
      unawaited(CloudSyncService.instance.pushMedicine(medicine));
    }
  }

  Future<void> deactivateMedicine(String id, {bool sync = true}) async {
    final db = await database;
    await db.update('medicines', {'active': 0}, where: 'id = ?', whereArgs: [id]);
    if (sync) {
      final rows = await db.query('medicines', where: 'id = ?', whereArgs: [id]);
      if (rows.isNotEmpty) {
        unawaited(CloudSyncService.instance.pushMedicine(Medicine.fromMap(rows.first)));
      }
    }
  }

  /// Permanently removes a medicine record (used by the "Delete" action,
  /// as opposed to "Stop" which just deactivates it but keeps history).
  Future<void> deleteMedicine(String id, {bool sync = true}) async {
    final db = await database;
    await db.delete('medicines', where: 'id = ?', whereArgs: [id]);
    if (sync) unawaited(CloudSyncService.instance.deleteMedicine(id));
  }

  // ---------- Prescriptions ----------
  Future<void> insertPrescription(Prescription p, {bool sync = true}) async {
    final db = await database;
    await db.insert('prescriptions', p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    if (sync) unawaited(CloudSyncService.instance.pushPrescription(p));
  }

  Future<List<Prescription>> getPrescriptions() async {
    final db = await database;
    final rows = await db.query('prescriptions', orderBy: 'dateAdded DESC');
    return rows.map((r) => Prescription.fromMap(r)).toList();
  }

  Future<void> deletePrescription(String id, {bool sync = true}) async {
    final db = await database;
    await db.delete('prescriptions', where: 'id = ?', whereArgs: [id]);
    if (sync) unawaited(CloudSyncService.instance.deletePrescription(id));
  }

  // ---------- Appointments ----------
  Future<void> insertAppointment(Appointment a, {bool sync = true}) async {
    final db = await database;
    await db.insert('appointments', a.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    if (sync) unawaited(CloudSyncService.instance.pushAppointment(a));
  }

  Future<List<Appointment>> getUpcomingAppointments() async {
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();
    final rows = await db.query('appointments',
        where: 'dateTime >= ?', whereArgs: [nowIso], orderBy: 'dateTime ASC');
    return rows.map((r) => Appointment.fromMap(r)).toList();
  }

  Future<void> deleteAppointment(String id, {bool sync = true}) async {
    final db = await database;
    await db.delete('appointments', where: 'id = ?', whereArgs: [id]);
    if (sync) unawaited(CloudSyncService.instance.deleteAppointment(id));
  }

  // ---------- Profiles (LEGACY — see note below) ----------
  // These local-profile methods are no longer used by AuthService, which
  // now talks to the cloud backend (backend/auth.js) for accounts. Left
  // here in case you want a local cache/fallback later; safe to delete
  // otherwise.
  Future<void> insertProfile(UserProfile p) async {
    final db = await database;
    await db.insert('profiles', p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateProfile(UserProfile p) async {
    final db = await database;
    await db.update('profiles', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
  }

  Future<UserProfile?> getProfileByEmail(String email) async {
    final db = await database;
    final rows =
        await db.query('profiles', where: 'email = ?', whereArgs: [email]);
    if (rows.isEmpty) return null;
    return UserProfile.fromMap(rows.first);
  }

  Future<UserProfile?> getProfileById(String id) async {
    final db = await database;
    final rows = await db.query('profiles', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return UserProfile.fromMap(rows.first);
  }

  // ---------- Health records ----------
  Future<void> insertHealthRecord(HealthRecord r, {bool sync = true}) async {
    final db = await database;
    await db.insert('health_records', r.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    if (sync) unawaited(CloudSyncService.instance.pushHealthRecord(r));
  }

  Future<List<HealthRecord>> getHealthRecords() async {
    final db = await database;
    final rows = await db.query('health_records', orderBy: 'date DESC');
    return rows.map((r) => HealthRecord.fromMap(r)).toList();
  }

  Future<void> deleteHealthRecord(String id, {bool sync = true}) async {
    final db = await database;
    await db.delete('health_records', where: 'id = ?', whereArgs: [id]);
    if (sync) unawaited(CloudSyncService.instance.deleteHealthRecord(id));
  }

  // ---------- Medical reports ----------
  Future<void> insertMedicalReport(MedicalReport r, {bool sync = true}) async {
    final db = await database;
    await db.insert('medical_reports', r.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    if (sync) unawaited(CloudSyncService.instance.pushMedicalReport(r));
  }

  Future<List<MedicalReport>> getMedicalReports() async {
    final db = await database;
    final rows = await db.query('medical_reports', orderBy: 'uploadedDate DESC');
    return rows.map((r) => MedicalReport.fromMap(r)).toList();
  }

  Future<void> deleteMedicalReport(String id, {bool sync = true}) async {
    final db = await database;
    await db.delete('medical_reports', where: 'id = ?', whereArgs: [id]);
    if (sync) unawaited(CloudSyncService.instance.deleteMedicalReport(id));
  }
}
