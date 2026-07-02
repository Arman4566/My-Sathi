class Appointment {
  final String id;
  final String doctorName;
  final String location;
  final DateTime dateTime;
  final String notes;
  final bool reminderSet;

  Appointment({
    required this.id,
    required this.doctorName,
    required this.location,
    required this.dateTime,
    this.notes = '',
    this.reminderSet = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'doctorName': doctorName,
      'location': location,
      'dateTime': dateTime.toIso8601String(),
      'notes': notes,
      'reminderSet': reminderSet ? 1 : 0,
    };
  }

  factory Appointment.fromMap(Map<String, dynamic> map) {
    return Appointment(
      id: map['id'],
      doctorName: map['doctorName'],
      location: map['location'] ?? '',
      dateTime: DateTime.parse(map['dateTime']),
      notes: map['notes'] ?? '',
      reminderSet: map['reminderSet'] == 1,
    );
  }
}
