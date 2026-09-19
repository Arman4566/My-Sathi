/// Metadata for a saved "Sathi AI Diagnostic Report" (chest X-ray, real
/// pretrained-model pipeline). The actual PDF bytes are fetched
/// separately (see XrayReportService.downloadPdf) rather than kept here
/// — they can be a few hundred KB and this model backs list views.
class XrayReport {
  final String id;
  final String title;
  final String primaryFinding;
  final double confidence;
  final String confidenceBand;
  final String modelId;
  final DateTime createdAt;

  XrayReport({
    required this.id,
    required this.title,
    required this.primaryFinding,
    required this.confidence,
    required this.confidenceBand,
    required this.modelId,
    required this.createdAt,
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
