/// One turn of the phone call transcript — either the AI assistant
/// speaking, or the receptionist/doctor's side (transcribed by Twilio's
/// speech recognition, so it may be imperfect).
class CallTranscriptTurn {
  final String role; // 'assistant' | 'them'
  final String text;

  CallTranscriptTurn({required this.role, required this.text});

  factory CallTranscriptTurn.fromJson(Map<String, dynamic> json) {
    return CallTranscriptTurn(
      role: json['role'] as String,
      text: json['text'] as String,
    );
  }
}

/// An AI-placed phone call to a doctor's office to book/confirm an
/// appointment. Mirrors backend/appointment_calls.js's `toJson`.
class AppointmentCall {
  final String id;
  final String? doctorName;
  final String doctorPhone;
  final String requestedDate;
  final String requestedTime;
  final String? patientName;
  final String notes;
  // queued | ringing | in_progress | completed | no_answer | busy | failed | canceled
  final String status;
  // confirmed | declined | needs_followup | unclear | null (until completed)
  final String? outcome;
  final String? outcomeSummary;
  final DateTime? confirmedDateTime;
  final List<CallTranscriptTurn> transcript;
  final bool isSimulated;
  final DateTime createdAt;

  AppointmentCall({
    required this.id,
    this.doctorName,
    required this.doctorPhone,
    required this.requestedDate,
    required this.requestedTime,
    this.patientName,
    this.notes = '',
    required this.status,
    this.outcome,
    this.outcomeSummary,
    this.confirmedDateTime,
    this.transcript = const [],
    this.isSimulated = false,
    required this.createdAt,
  });

  bool get isFinished =>
      const ['completed', 'no_answer', 'busy', 'failed', 'canceled'].contains(status);

  factory AppointmentCall.fromJson(Map<String, dynamic> json) {
    return AppointmentCall(
      id: json['id'] as String,
      doctorName: json['doctorName'] as String?,
      doctorPhone: json['doctorPhone'] as String,
      requestedDate: json['requestedDate'] as String,
      requestedTime: json['requestedTime'] as String,
      patientName: json['patientName'] as String?,
      notes: (json['notes'] as String?) ?? '',
      status: json['status'] as String,
      outcome: json['outcome'] as String?,
      outcomeSummary: json['outcomeSummary'] as String?,
      confirmedDateTime: json['confirmedDateTime'] != null
          ? DateTime.tryParse(json['confirmedDateTime'] as String)
          : null,
      transcript: ((json['transcript'] as List?) ?? [])
          .map((t) => CallTranscriptTurn.fromJson(t as Map<String, dynamic>))
          .toList(),
      isSimulated: (json['isSimulated'] as bool?) ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
