import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/lab_value.dart';
import '../services/lab_trend_analyzer.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';

/// A "nice" (round-number) axis range: e.g. for data spanning 168-190 this
/// picks something like min 160 / max 200 / step 10, rather than the raw
/// data bounds — which is what stops the gridlines and their labels from
/// landing at ugly, overlapping values like 209.6 and 210 on top of each
/// other.
class _AxisScale {
  final double min;
  final double max;
  final double step;
  const _AxisScale(this.min, this.max, this.step);
}

_AxisScale _niceAxisScale(double dataMin, double dataMax, {int targetTicks = 5}) {
  if (dataMax <= dataMin) {
    // A flat line (or a single repeated value) has zero range — invent a
    // sensible one so the chart isn't a single point in empty space.
    final pad = dataMin.abs() * 0.1 + 1;
    dataMin -= pad;
    dataMax += pad;
  }
  final range = dataMax - dataMin;
  final rawStep = range / targetTicks;
  final magnitude = math.pow(10, (math.log(rawStep) / math.ln10).floor()).toDouble();
  final residual = rawStep / magnitude;
  double step;
  if (residual > 5) {
    step = 10 * magnitude;
  } else if (residual > 2) {
    step = 5 * magnitude;
  } else if (residual > 1) {
    step = 2 * magnitude;
  } else {
    step = magnitude;
  }
  final niceMin = (dataMin / step).floor() * step;
  final niceMax = (dataMax / step).ceil() * step;
  // Guard against floating point ever producing a zero step.
  return _AxisScale(niceMin, niceMax, step <= 0 ? 1 : step);
}

/// Full month-over-month chart for one test (e.g. every "Hemoglobin"
/// reading pulled from your Jan/Feb/March... reports), with a verdict on
/// whether it's improving, worsening, or holding steady.
class LabTrendDetailScreen extends StatelessWidget {
  final String testName;
  final List<LabTestValue> values; // sorted oldest-first, length >= 2

  const LabTrendDetailScreen({
    super.key,
    required this.testName,
    required this.values,
  });

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().languageCode;
    final result = analyzeLabTrend(values);
    final unit = values.last.unit;
    final hasRange = values.any((v) => v.hasRange);
    // Reference range can vary slightly report to report (different
    // labs); use the most recent stated range as the one drawn on the
    // chart, since that's the one that matters for "is my latest result
    // normal".
    final latestWithRange = values.lastWhere((v) => v.hasRange, orElse: () => values.last);

    // One combined min/max/step for the Y axis, computed once from every
    // value AND the reference range together (not the two patched-together
    // formulas the old code used) — this is what keeps the gridlines,
    // their labels, and the reference-range lines all consistent with each
    // other instead of drifting apart and overlapping.
    final dataMin = values.map((v) => v.value).reduce(math.min);
    final dataMax = values.map((v) => v.value).reduce(math.max);
    final yMin = hasRange && latestWithRange.refLow! < dataMin ? latestWithRange.refLow! : dataMin;
    final yMax = hasRange && latestWithRange.refHigh! > dataMax ? latestWithRange.refHigh! : dataMax;
    final yScale = _niceAxisScale(yMin, yMax);

    // With only a handful of points, label every one; with many, thin the
    // labels out so dates don't collide into unreadable clutter.
    final labelEvery = (values.length / 6).ceil().clamp(1, values.length);
    final showPermanentValueLabels = values.length <= 4;

    final spots = [
      for (int i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i].value),
    ];
    final lineBar = LineChartBarData(
      spots: spots,
      isCurved: false,
      color: const Color(0xFF5B7CFA),
      barWidth: 3,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, bar, index) {
          final v = values[index];
          return FlDotCirclePainter(
            radius: 4,
            color: v.isAbnormal ? Colors.orange : const Color(0xFF5B7CFA),
            strokeWidth: 2,
            strokeColor: Colors.white,
          );
        },
      ),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF5B7CFA).withValues(alpha: 0.18),
            const Color(0xFF5B7CFA).withValues(alpha: 0.0),
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(testName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _VerdictBanner(result: result, unit: unit, lang: lang),
          const SizedBox(height: 20),
          SizedBox(
            height: 280,
            child: Padding(
              padding: const EdgeInsets.only(right: 16, top: 32, left: 4),
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (values.length - 1).toDouble(),
                  minY: yScale.min,
                  maxY: yScale.max,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: yScale.step,
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        interval: yScale.step,
                        getTitlesWidget: (v, meta) => Text(
                          v.toStringAsFixed(yScale.step < 1 ? 1 : 0),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: 1,
                        getTitlesWidget: (v, meta) {
                          final i = v.round();
                          if (i < 0 ||
                              i >= values.length ||
                              (i % labelEvery != 0 && i != values.length - 1)) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              DateFormat('d MMM').format(values[i].date),
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  extraLinesData: hasRange
                      ? ExtraLinesData(horizontalLines: [
                          HorizontalLine(
                            y: latestWithRange.refLow!,
                            color: Colors.green.withValues(alpha: 0.6),
                            strokeWidth: 1,
                            dashArray: [6, 4],
                          ),
                          HorizontalLine(
                            y: latestWithRange.refHigh!,
                            color: Colors.green.withValues(alpha: 0.6),
                            strokeWidth: 1,
                            dashArray: [6, 4],
                          ),
                        ])
                      : null,
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      getTooltipItems: (spots) => spots.map((s) {
                        final v = values[s.x.toInt()];
                        return LineTooltipItem(
                          '${DateFormat('d MMM yyyy').format(v.date)}\n${_fmt(v.value)}${unit.isNotEmpty ? ' $unit' : ''}',
                          const TextStyle(
                              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        );
                      }).toList(),
                    ),
                  ),
                  // For a short trend (a handful of readings, the common
                  // case right after uploading two reports) label every
                  // point's value directly on the chart, so the change
                  // between readings is visible at a glance without having
                  // to tap each dot.
                  showingTooltipIndicators: showPermanentValueLabels
                      ? [
                          for (int i = 0; i < spots.length; i++)
                            ShowingTooltipIndicators([LineBarSpot(lineBar, 0, spots[i])]),
                        ]
                      : [],
                  lineBarsData: [lineBar],
                ),
              ),
            ),
          ),
          if (hasRange) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 14, height: 2, color: Colors.green.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Text(
                  AppText.t('normal_range_label', lang).replaceFirst(
                      '{range}',
                      '${latestWithRange.refLow}–${latestWithRange.refHigh}'
                      '${unit.isNotEmpty ? ' $unit' : ''}'),
                  style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Text(AppText.t('all_readings', lang), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...values.reversed.map((v) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(DateFormat('d MMM yyyy').format(v.date)),
                trailing: Text(
                  '${_fmt(v.value)}${unit.isNotEmpty ? ' $unit' : ''}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: v.isAbnormal ? Colors.orange : null,
                  ),
                ),
              )),
          const SizedBox(height: 12),
          Text(
            AppText.t('lab_trend_disclaimer', lang),
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
          ),
        ],
      ),
    );
  }

}

/// Trims trailing zeros so labels read "190" instead of "190.0" for
/// whole-number results, while still showing "13.2" where the decimal is
/// meaningful.
String _fmt(double v) => v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toString();

class _VerdictBanner extends StatelessWidget {
  final LabTrendResult result;
  final String unit;
  final String lang;
  const _VerdictBanner({required this.result, required this.unit, required this.lang});

  @override
  Widget build(BuildContext context) {
    late String headline;
    late Color color;
    late IconData icon;
    switch (result.trend) {
      case LabTrend.improving:
        headline = AppText.t('trend_headline_improving', lang);
        color = Colors.green;
        icon = Icons.trending_up;
        break;
      case LabTrend.worsening:
        headline = AppText.t('trend_headline_worsening', lang);
        color = Colors.red;
        icon = Icons.trending_down;
        break;
      case LabTrend.increasing:
        headline = AppText.t('trend_headline_increasing', lang);
        color = Colors.blueGrey;
        icon = Icons.trending_up;
        break;
      case LabTrend.decreasing:
        headline = AppText.t('trend_headline_decreasing', lang);
        color = Colors.blueGrey;
        icon = Icons.trending_down;
        break;
      case LabTrend.stable:
        headline = AppText.t('trend_headline_stable', lang);
        color = Colors.blueGrey;
        icon = Icons.trending_flat;
        break;
    }

    final changeText = AppText.t('trend_change_detail', lang)
        .replaceFirst('{from}', '${_fmt(result.first.value)}${unit.isNotEmpty ? ' $unit' : ''}')
        .replaceFirst('{to}', '${_fmt(result.latest.value)}${unit.isNotEmpty ? ' $unit' : ''}')
        // Full date, not just month/year: two reports from the same month
        // (or even the same day, as with two panels from one visit) used to
        // both collapse to identical-looking "Sep 2026 → Sep 2026" text,
        // which read as if nothing had changed even though the numbers
        // clearly had.
        .replaceFirst('{fromDate}', DateFormat('d MMM yyyy').format(result.first.date))
        .replaceFirst('{toDate}', DateFormat('d MMM yyyy').format(result.latest.date));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline,
                    style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15)),
                const SizedBox(height: 4),
                Text(changeText, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
