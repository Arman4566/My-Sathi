/// How often a medicine should be taken.
/// - daily: every day at the given times
/// - custom: only on selected weekdays (see [Medicine.customDays])
enum MedicineFrequency { daily, custom }

class Medicine {
  final String id;
  final String name;
  final String dosage; // e.g. "500mg"
  final String instructions; // e.g. "After food"
  final List<String> times; // e.g. ["08:00", "20:00"]
  final DateTime startDate;
  final DateTime? endDate; // null = ongoing, no auto-expiry
  final String? prescriptionId; // links back to the scanned prescription
  final bool active;
  final MedicineFrequency frequency;
  final List<int> customDays; // DateTime.monday(1) .. DateTime.sunday(7)
  final String? photoPath; // optional photo of the medicine/packaging
  final String? prescribedBy; // doctor's name, included in reminder alarms

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
    this.frequency = MedicineFrequency.daily,
    this.customDays = const [],
    this.photoPath,
    this.prescribedBy,
  });

  /// True if today is past this medicine's end date — used to
  /// automatically retire old medicines instead of reminding forever.
  bool get isExpired =>
      endDate != null && DateTime.now().isAfter(endDate!);

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
      'frequency': frequency.name,
      'customDays': customDays.join(','),
      'photoPath': photoPath,
      'prescribedBy': prescribedBy,
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
      frequency: MedicineFrequency.values.firstWhere(
        (f) => f.name == (map['frequency'] ?? 'daily'),
        orElse: () => MedicineFrequency.daily,
      ),
      customDays: (map['customDays'] as String? ?? '').isEmpty
          ? []
          : (map['customDays'] as String)
              .split(',')
              .map((e) => int.parse(e))
              .toList(),
      photoPath: map['photoPath'],
      prescribedBy: map['prescribedBy'],
    );
  }

  Medicine copyWith({
    String? name,
    String? dosage,
    String? instructions,
    List<String>? times,
    DateTime? startDate,
    DateTime? endDate,
    bool? active,
    MedicineFrequency? frequency,
    List<int>? customDays,
    String? photoPath,
    String? prescribedBy,
  }) {
    return Medicine(
      id: id,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      instructions: instructions ?? this.instructions,
      times: times ?? this.times,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      prescriptionId: prescriptionId,
      active: active ?? this.active,
      frequency: frequency ?? this.frequency,
      customDays: customDays ?? this.customDays,
      photoPath: photoPath ?? this.photoPath,
      prescribedBy: prescribedBy ?? this.prescribedBy,
    );
  }
}
