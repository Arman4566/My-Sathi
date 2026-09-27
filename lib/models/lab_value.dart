/// One structured test reading extracted from a blood/lab report — e.g.
/// "Hemoglobin: 13.2 g/dL (13.0-17.0)". A single MedicalReport (one
/// upload) can produce many of these (a CBC panel alone has a dozen).
///
/// This is what makes month-over-month trend graphs possible: the report
/// itself only stores free-text (rawText/summary), but trends need the
/// same test tracked as a *number* across multiple dated reports.
class LabTestValue {
  final String id;
  final String reportId; // links back to MedicalReport.id
  final String testName; // normalized, e.g. "Hemoglobin"
  final double value;
  final String unit; // e.g. "g/dL" — may be empty if not stated
  final double? refLow; // normal-range low, if the report stated one
  final double? refHigh; // normal-range high, if the report stated one
  final DateTime date; // the report's date (not upload time necessarily)

  LabTestValue({
    required this.id,
    required this.reportId,
    required this.testName,
    required this.value,
    required this.unit,
    required this.date,
    this.refLow,
    this.refHigh,
  });

  bool get hasRange => refLow != null && refHigh != null;
  bool get isAbnormal =>
      hasRange && (value < refLow! || value > refHigh!);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'reportId': reportId,
      'testName': testName,
      'value': value,
      'unit': unit,
      'refLow': refLow,
      'refHigh': refHigh,
      'date': date.toIso8601String(),
    };
  }

  factory LabTestValue.fromMap(Map<String, dynamic> map) {
    return LabTestValue(
      id: map['id'],
      reportId: map['reportId'] ?? '',
      testName: map['testName'] ?? '',
      value: (map['value'] as num).toDouble(),
      unit: map['unit'] ?? '',
      refLow: map['refLow'] == null ? null : (map['refLow'] as num).toDouble(),
      refHigh:
          map['refHigh'] == null ? null : (map['refHigh'] as num).toDouble(),
      date: DateTime.parse(map['date']),
    );
  }

  /// Parses one entry of the AI backend's `/api/extract-lab-values`
  /// response. [reportId]/[date]/[id] are filled in by the caller since
  /// the backend only returns the test itself, not report metadata.
  factory LabTestValue.fromAiJson(
    Map<String, dynamic> j, {
    required String id,
    required String reportId,
    required DateTime date,
  }) {
    return LabTestValue(
      id: id,
      reportId: reportId,
      date: date,
      testName: (j['test'] ?? '').toString().trim(),
      value: double.tryParse(j['value'].toString()) ?? 0,
      unit: (j['unit'] ?? '').toString().trim(),
      refLow: j['low'] == null ? null : double.tryParse(j['low'].toString()),
      refHigh:
          j['high'] == null ? null : double.tryParse(j['high'].toString()),
    );
  }
}
