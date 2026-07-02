import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/medicine.dart';
import '../models/prescription.dart';
import '../models/appointment.dart';

/// Single source of truth for all local persistence.
/// Everything lives on-device (SQLite) so patient health data
/// never leaves the phone unless the user explicitly exports it.
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
      version: 1,
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
            active INTEGER
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
      },
    );
  }

  // ---------- Medicines ----------
  Future<void> insertMedicine(Medicine m) async {
    final db = await database;
    await db.insert('medicines', m.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Medicine>> getActiveMedicines() async {
    final db = await database;
    final rows = await db.query('medicines', where: 'active = 1');
    return rows.map((r) => Medicine.fromMap(r)).toList();
  }

  Future<void> deactivateMedicine(String id) async {
    final db = await database;
    await db.update('medicines', {'active': 0}, where: 'id = ?', whereArgs: [id]);
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
}
