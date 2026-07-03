class HealthRecord {
  final String id;
  final DateTime date;
  final double? weightKg;
  final String? bloodPressure; // e.g. "120/80"
  final double? sugarLevel; // mg/dL
  final String notes;

  HealthRecord({
    required this.id,
    required this.date,
    this.weightKg,
    this.bloodPressure,
    this.sugarLevel,
    this.notes = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'weightKg': weightKg,
      'bloodPressure': bloodPressure,
      'sugarLevel': sugarLevel,
      'notes': notes,
    };
  }

  factory HealthRecord.fromMap(Map<String, dynamic> map) {
    return HealthRecord(
      id: map['id'],
      date: DateTime.parse(map['date']),
      weightKg: map['weightKg'],
      bloodPressure: map['bloodPressure'],
      sugarLevel: map['sugarLevel'],
      notes: map['notes'] ?? '',
    );
  }
}
