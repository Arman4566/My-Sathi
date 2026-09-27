import '../models/lab_value.dart';

/// Which direction a test's readings are heading, in terms that matter to
/// a patient — not just "the number went up".
enum LabTrend {
  /// Was outside the normal range and has moved closer to (or into) it.
  improving,

  /// Was in/near the normal range and has moved further outside it.
  worsening,

  /// Within the normal range throughout, or too small a change to call.
  stable,

  /// No reference range was available, so "better/worse" can't be
  /// determined — only the raw direction of change is shown.
  increasing,
  decreasing,
}

class LabTrendResult {
  final LabTrend trend;
  final LabTestValue first;
  final LabTestValue latest;
  final double changeAbs;
  final double? changePct;

  LabTrendResult({
    required this.trend,
    required this.first,
    required this.latest,
    required this.changeAbs,
    this.changePct,
  });
}

/// How far outside its normal range a reading is (0 if inside it, or if
/// no range is known).
double _distanceOutsideRange(LabTestValue v) {
  if (!v.hasRange) return 0;
  if (v.value < v.refLow!) return v.refLow! - v.value;
  if (v.value > v.refHigh!) return v.value - v.refHigh!;
  return 0;
}

/// Works out whether a test is trending toward or away from normal,
/// purely from the numbers the patient's own reports contain — no
/// diagnosis, no interpretation of what the test means medically, just
/// "is this reading closer to or further from the stated normal range
/// than it used to be". [values] must be sorted oldest-first and have
/// at least 2 entries.
LabTrendResult analyzeLabTrend(List<LabTestValue> values) {
  assert(values.length >= 2);
  final first = values.first;
  final latest = values.last;
  final changeAbs = latest.value - first.value;
  final changePct = first.value == 0 ? null : (changeAbs / first.value.abs()) * 100;

  if (first.hasRange || latest.hasRange) {
    final firstDist = _distanceOutsideRange(first);
    final latestDist = _distanceOutsideRange(latest);
    LabTrend trend;
    if (firstDist == 0 && latestDist == 0) {
      trend = LabTrend.stable;
    } else if (latestDist < firstDist) {
      trend = LabTrend.improving;
    } else if (latestDist > firstDist) {
      trend = LabTrend.worsening;
    } else {
      trend = LabTrend.stable;
    }
    return LabTrendResult(
        trend: trend,
        first: first,
        latest: latest,
        changeAbs: changeAbs,
        changePct: changePct);
  }

  // No normal range stated anywhere in the series — fall back to a
  // plain direction-of-change reading. A <5% move is treated as noise
  // rather than a real trend.
  final trend = (changePct == null || changePct.abs() < 5)
      ? LabTrend.stable
      : (changeAbs > 0 ? LabTrend.increasing : LabTrend.decreasing);
  return LabTrendResult(
      trend: trend,
      first: first,
      latest: latest,
      changeAbs: changeAbs,
      changePct: changePct);
}
