import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/medicine.dart';
import '../models/prescription.dart';
import '../models/appointment.dart';
import '../models/user_profile.dart';
import '../models/health_record.dart';

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
      version: 2,
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
            customDays TEXT
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
            gender TEXT
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
      },
    );
  }

  // ---------- Medicines ----------
  Future<void> insertMedicine(Medicine m) async {
    final db = await database;
    await db.insert('medicines', m.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateMedicine(Medicine m) async {
    final db = await database;
    await db.update('medicines', m.toMap(), where: 'id = ?', whereArgs: [m.id]);
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
    await db.update(
      'medicines',
      {'active': 0},
      where: 'active = 1 AND endDate IS NOT NULL AND endDate < ?',
      whereArgs: [nowIso],
    );
  }

  Future<void> deactivateMedicine(String id) async {
    final db = await database;
    await db.update('medicines', {'active': 0}, where: 'id = ?', whereArgs: [id]);
  }

  /// Permanently removes a medicine record (used by the "Delete" action,
  /// as opposed to "Stop" which just deactivates it but keeps history).
  Future<void> deleteMedicine(String id) async {
    final db = await database;
    await db.delete('medicines', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Prescriptions ----------
  Future<void> insertPrescription(Prescription p) async {
    final db = await database;
    await db.insert('prescriptions', p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Prescription>> getPrescriptions() async {
    final db = await database;
    final rows = await db.query('prescriptions', orderBy: 'dateAdded DESC');
    return rows.map((r) => Prescription.fromMap(r)).toList();
  }

  Future<void> deletePrescription(String id) async {
    final db = await database;
    await db.delete('prescriptions', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Appointments ----------
  Future<void> insertAppointment(Appointment a) async {
    final db = await database;
    await db.insert('appointments', a.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Appointment>> getUpcomingAppointments() async {
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();
    final rows = await db.query('appointments',
        where: 'dateTime >= ?', whereArgs: [nowIso], orderBy: 'dateTime ASC');
    return rows.map((r) => Appointment.fromMap(r)).toList();
  }

  Future<void> deleteAppointment(String id) async {
    final db = await database;
    await db.delete('appointments', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Profiles (local login) ----------
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
  Future<void> insertHealthRecord(HealthRecord r) async {
    final db = await database;
    await db.insert('health_records', r.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<HealthRecord>> getHealthRecords() async {
    final db = await database;
    final rows = await db.query('health_records', orderBy: 'date DESC');
    return rows.map((r) => HealthRecord.fromMap(r)).toList();
  }

  Future<void> deleteHealthRecord(String id) async {
    final db = await database;
    await db.delete('health_records', where: 'id = ?', whereArgs: [id]);
  }
}
