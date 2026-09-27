import 'package:flutter/material.dart';
import '../models/interaction_check.dart';
import '../services/app_text.dart';

Color _severityColor(InteractionSeverity s) {
  switch (s) {
    case InteractionSeverity.major:
      return Colors.redAccent;
    case InteractionSeverity.moderate:
      return Colors.amber.shade800;
    case InteractionSeverity.minor:
      return Colors.blueGrey;
  }
}

String _severityLabel(InteractionSeverity s, String lang) {
  switch (s) {
    case InteractionSeverity.major:
      return AppText.t('interaction_severity_major', lang);
    case InteractionSeverity.moderate:
      return AppText.t('interaction_severity_moderate', lang);
    case InteractionSeverity.minor:
      return AppText.t('interaction_severity_minor', lang);
  }
}

/// Shows the "AI Safety & Interaction Guard" result as a dialog and
/// returns true if the user chose to continue saving, false if they
/// want to go back and review first.
///
/// Intentionally non-blocking by default: this is a warning surface,
/// not a hard stop — see INTERACTION_CHECK_PROMPT in server.js and the
/// "AI suggests, human confirms" pattern used throughout the app. Even
/// a "major" interaction only gets a stronger visual banner and a
/// relabeled confirm button, never a disabled one, because the AI check
/// can be wrong in either direction and the patient (or their doctor)
/// may already know it's fine.
///
/// [unavailable] is true when the check itself failed (e.g. AI
/// overloaded/quota) — shown as a neutral notice rather than as if
/// nothing was found, so the absence of warnings isn't misread as a
/// clean bill of health.
Future<bool> showInteractionWarningDialog(
  BuildContext context, {
  required String lang,
  InteractionCheckResult? result,
  bool unavailable = false,
}) async {
  // Nothing to show and the check itself succeeded cleanly — no need to
  // interrupt the save flow with an empty dialog.
  if (!unavailable && (result == null || !result.hasAnyWarning)) {
    return true;
  }

  final hasMajor = result?.hasAnyMajorInteraction ?? false;

  final proceed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.health_and_safety_outlined,
              color: hasMajor ? Colors.redAccent : Colors.amber.shade800),
          const SizedBox(width: 8),
          Expanded(child: Text(AppText.t('interaction_warning_title', lang))),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (unavailable) ...[
                Text(
                  AppText.t('interaction_check_unavailable', lang),
                  style: TextStyle(color: Theme.of(ctx).hintColor),
                ),
              ] else ...[
                if (hasMajor)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      AppText.t('interaction_major_banner', lang),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                for (final r in result!.results)
                  if (r.hasAnyWarning) ...[
                    Text(r.medicineName,
                        style: Theme.of(ctx)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    if (r.foodPrecaution.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.restaurant_outlined, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${AppText.t('interaction_food_precaution', lang)}: ${r.foodPrecaution}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    for (final i in r.interactions)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _severityColor(i.severity).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border(
                            left: BorderSide(
                                color: _severityColor(i.severity), width: 3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Pairing line: severity badge + which
                            // medicine this is with — the "what".
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _severityColor(i.severity),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _severityLabel(i.severity, lang),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    AppText.t('interaction_with', lang)
                                        .replaceFirst('{medicine}', i.withMedicine),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                            // Reason line, always shown directly below
                            // the pairing — the "why". Never collapsed
                            // or hidden behind a tap; per feature ask,
                            // the reason must sit right under the
                            // warning itself.
                            if (i.reason.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${AppText.t('interaction_reason_label', lang)}: ${i.reason}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                          ],
                        ),
                      ),
                    const Divider(height: 18),
                  ],
                if (!result.hasAnyWarning)
                  Text(AppText.t('interaction_none_found', lang)),
              ],
              const SizedBox(height: 4),
              Text(
                AppText.t('interaction_disclaimer', lang),
                style: TextStyle(
                    fontSize: 12, color: Theme.of(ctx).hintColor),
              ),
            ],
          ),
        ),
      ),
      actions: unavailable
          ? [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(AppText.t('interaction_ok', lang)),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(AppText.t('interaction_go_back', lang)),
              ),
              ElevatedButton(
                style: hasMajor
                    ? ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent)
                    : null,
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(AppText.t('interaction_continue_anyway', lang)),
              ),
            ],
    ),
  );

  return proceed ?? false;
}
