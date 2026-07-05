class MedicalReport {
  final String id;
  final String title;
  final String filePath;
  final String rawText; // OCR-extracted text
  final String summary; // AI-generated plain-language summary
  final DateTime uploadedDate;

  MedicalReport({
    required this.id,
    required this.title,
    required this.filePath,
    required this.rawText,
    required this.summary,
    required this.uploadedDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'filePath': filePath,
      'rawText': rawText,
      'summary': summary,
      'uploadedDate': uploadedDate.toIso8601String(),
    };
  }

  factory MedicalReport.fromMap(Map<String, dynamic> map) {
    return MedicalReport(
      id: map['id'],
      title: map['title'],
      filePath: map['filePath'],
      rawText: map['rawText'] ?? '',
      summary: map['summary'] ?? '',
      uploadedDate: DateTime.parse(map['uploadedDate']),
    );
  }
}
