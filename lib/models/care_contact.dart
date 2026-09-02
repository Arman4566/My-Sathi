/// A family member/caregiver's phone number the patient wants notified
/// over WhatsApp — either when a medicine dose looks missed, before an
/// upcoming appointment, or both. The actual sending happens server-side
/// (see backend/whatsapp_reminders.js) so it works even if this phone/app
/// isn't open at the time.
class CareContact {
  final String id;
  final String name;
  final String phone; // E.164 format, e.g. +919876543210
  final bool notifyMissedMedicine;
  final bool notifyBeforeAppointment;

  CareContact({
    required this.id,
    required this.name,
    required this.phone,
    this.notifyMissedMedicine = true,
    this.notifyBeforeAppointment = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'notifyMissedMedicine': notifyMissedMedicine ? 1 : 0,
      'notifyBeforeAppointment': notifyBeforeAppointment ? 1 : 0,
    };
  }

  factory CareContact.fromMap(Map<String, dynamic> map) {
    return CareContact(
      id: map['id'],
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      notifyMissedMedicine: map['notifyMissedMedicine'] == 1,
      notifyBeforeAppointment: map['notifyBeforeAppointment'] == 1,
    );
  }

  CareContact copyWith({
    String? name,
    String? phone,
    bool? notifyMissedMedicine,
    bool? notifyBeforeAppointment,
  }) {
    return CareContact(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      notifyMissedMedicine: notifyMissedMedicine ?? this.notifyMissedMedicine,
      notifyBeforeAppointment: notifyBeforeAppointment ?? this.notifyBeforeAppointment,
    );
  }
}
