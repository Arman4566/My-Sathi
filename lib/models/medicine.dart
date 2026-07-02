class Medicine {
  final String id;
  final String name;
  final String dosage; // e.g. "500mg"
  final String instructions; // e.g. "After food"
  final List<String> times; // e.g. ["08:00", "20:00"]
  final DateTime startDate;
  final DateTime? endDate;
  final String? prescriptionId; // links back to the scanned prescription
  final bool active;

  Medicine({
    required this.id,
    required this.name,
    required this.dosage,
    required this.instructions,
    required this.times,
    required this.startDate,
    this.endDate,
    this.prescriptionId,
    this.active = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'dosage': dosage,
      'instructions': instructions,
      'times': times.join(','),
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'prescriptionId': prescriptionId,
      'active': active ? 1 : 0,
    };
  }

  factory Medicine.fromMap(Map<String, dynamic> map) {
    return Medicine(
      id: map['id'],
      name: map['name'],
      dosage: map['dosage'],
      instructions: map['instructions'] ?? '',
      times: (map['times'] as String).isEmpty
          ? []
          : (map['times'] as String).split(','),
      startDate: DateTime.parse(map['startDate']),
      endDate: map['endDate'] != null ? DateTime.parse(map['endDate']) : null,
      prescriptionId: map['prescriptionId'],
      active: map['active'] == 1,
    );
  }
}
