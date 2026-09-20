/// Metadata for a saved "Sathi AI Diagnostic Report" (chest X-ray, real
/// pretrained-model pipeline). The PDF bytes themselves live either on
/// disk (localPdfPath, once saved on this device — see
/// LocalFileStorageService) or are fetched from the backend on demand
/// (XrayReportService.downloadPdf) and then cached locally for next time.
class XrayReport {
  final String id;
  final String title;
  final String primaryFinding;
  final double confidence;
  final String confidenceBand;
  final String modelId;
  final DateTime createdAt;
  // Set once this report's PDF/photo have been saved to this device's
  // persistent storage — null means "not cached here yet, only on the
  // backend" (e.g. generated on a different device).
  final String? localPdfPath;
  final String? localPhotoPath;

  XrayReport({
    required this.id,
    required this.title,
    required this.primaryFinding,
    required this.confidence,
    required this.confidenceBand,
    required this.modelId,
    required this.createdAt,
    this.localPdfPath,
    this.localPhotoPath,
  });

  factory XrayReport.fromJson(Map<String, dynamic> j) {
    return XrayReport(
      id: j['id'] as String,
      title: j['title'] as String? ?? 'Chest X-ray report',
      primaryFinding: j['primaryFinding'] as String? ?? '',
      confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
      confidenceBand: j['confidenceBand'] as String? ?? '',
      modelId: j['modelId'] as String? ?? '',
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  /// Local SQLite row -> model (see DatabaseService's xray_reports_local table).
  factory XrayReport.fromLocalMap(Map<String, dynamic> m) {
    return XrayReport(
      id: m['id'] as String,
      title: m['title'] as String? ?? 'Chest X-ray report',
      primaryFinding: m['primaryFinding'] as String? ?? '',
      confidence: (m['confidence'] as num?)?.toDouble() ?? 0,
      confidenceBand: m['confidenceBand'] as String? ?? '',
      modelId: m['modelId'] as String? ?? '',
      createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
      localPdfPath: m['localPdfPath'] as String?,
      localPhotoPath: m['localPhotoPath'] as String?,
    );
  }

  Map<String, dynamic> toLocalMap() {
    return {
      'id': id,
      'title': title,
      'primaryFinding': primaryFinding,
      'confidence': confidence,
      'confidenceBand': confidenceBand,
      'modelId': modelId,
      'createdAt': createdAt.toIso8601String(),
      'localPdfPath': localPdfPath,
      'localPhotoPath': localPhotoPath,
    };
  }

  XrayReport copyWith({String? localPdfPath, String? localPhotoPath}) {
    return XrayReport(
      id: id,
      title: title,
      primaryFinding: primaryFinding,
      confidence: confidence,
      confidenceBand: confidenceBand,
      modelId: modelId,
      createdAt: createdAt,
      localPdfPath: localPdfPath ?? this.localPdfPath,
      localPhotoPath: localPhotoPath ?? this.localPhotoPath,
    );
  }
}

/// Result of a freshly analyzed X-ray, returned directly from
/// POST /analyze (metadata + the PDF bytes, so the app doesn't need a
/// second round trip to show/download it right away).
class XrayAnalysisResult {
  final XrayReport report;
  final List<String> warnings;
  final List<int> pdfBytes;

  XrayAnalysisResult({
    required this.report,
    required this.warnings,
    required this.pdfBytes,
  });
}
