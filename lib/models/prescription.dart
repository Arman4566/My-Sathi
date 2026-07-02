class Prescription {
  final String id;
  final String imagePath; // local path to the scanned photo
  final String rawText; // raw OCR output, kept for reference/audit
  final String doctorName;
  final DateTime dateAdded;
  final String notes;

  Prescription({
    required this.id,
    required this.imagePath,
    required this.rawText,
    required this.doctorName,
    required this.dateAdded,
    this.notes = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'imagePath': imagePath,
      'rawText': rawText,
      'doctorName': doctorName,
      'dateAdded': dateAdded.toIso8601String(),
      'notes': notes,
    };
  }

  factory Prescription.fromMap(Map<String, dynamic> map) {
    return Prescription(
      id: map['id'],
      imagePath: map['imagePath'],
      rawText: map['rawText'],
      doctorName: map['doctorName'] ?? '',
      dateAdded: DateTime.parse(map['dateAdded']),
      notes: map['notes'] ?? '',
    );
  }
}
