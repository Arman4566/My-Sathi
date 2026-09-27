/// How serious a flagged drug-drug interaction is. Mirrors the three
/// tiers the backend's INTERACTION_CHECK_PROMPT is asked to use — see
/// backend/server.js.
enum InteractionSeverity { major, moderate, minor }

InteractionSeverity _severityFromString(String? s) {
  switch (s) {
    case 'major':
      return InteractionSeverity.major;
    case 'minor':
      return InteractionSeverity.minor;
    case 'moderate':
    default:
      return InteractionSeverity.moderate;
  }
}

/// One flagged interaction between the medicine being added and another
/// medicine (already-active, or another one in the same batch).
class DrugInteraction {
  final String withMedicine;
  final InteractionSeverity severity;
  // Plain-language explanation of the actual effect/risk (e.g. "Both
  // medicines lower blood pressure, so together they may drop it too
  // low") — always shown to the patient right below the pairing itself,
  // never hidden behind a "why" tap. See INTERACTION_CHECK_PROMPT in
  // server.js for why this must name the concrete effect, not just say
  // "these interact".
  final String reason;

  DrugInteraction({
    required this.withMedicine,
    required this.severity,
    required this.reason,
  });

  factory DrugInteraction.fromJson(Map<String, dynamic> j) {
    return DrugInteraction(
      withMedicine: j['withMedicine'] as String? ?? '',
      severity: _severityFromString(j['severity'] as String?),
      // 'description' kept as a fallback for a backend that hasn't been
      // redeployed with the renamed field yet.
      reason: (j['reason'] as String?) ?? (j['description'] as String?) ?? '',
    );
  }
}

/// Result for a single medicine being added: any flagged interactions
/// plus a general food/timing precaution for that medicine itself.
class MedicineInteractionResult {
  final String medicineName;
  final String foodPrecaution;
  final List<DrugInteraction> interactions;

  MedicineInteractionResult({
    required this.medicineName,
    required this.foodPrecaution,
    required this.interactions,
  });

  bool get hasAnyWarning => interactions.isNotEmpty || foodPrecaution.isNotEmpty;

  bool get hasMajorInteraction =>
      interactions.any((i) => i.severity == InteractionSeverity.major);

  factory MedicineInteractionResult.fromJson(Map<String, dynamic> j) {
    final list = (j['interactions'] as List?) ?? [];
    return MedicineInteractionResult(
      medicineName: j['medicineName'] as String? ?? '',
      foodPrecaution: j['foodPrecaution'] as String? ?? '',
      interactions: list
          .map((e) => DrugInteraction.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Full response from POST /api/check-interactions — one result per
/// medicine that was checked.
class InteractionCheckResult {
  final List<MedicineInteractionResult> results;

  InteractionCheckResult({required this.results});

  bool get hasAnyWarning => results.any((r) => r.hasAnyWarning);
  bool get hasAnyMajorInteraction => results.any((r) => r.hasMajorInteraction);

  factory InteractionCheckResult.fromJson(Map<String, dynamic> j) {
    final list = (j['results'] as List?) ?? [];
    return InteractionCheckResult(
      results: list
          .map((e) =>
              MedicineInteractionResult.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
