import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/lab_value.dart';
import '../services/lab_trend_analyzer.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';

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

    return Scaffold(
      appBar: AppBar(title: Text(testName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _VerdictBanner(result: result, unit: unit, lang: lang),
          const SizedBox(height: 20),
          SizedBox(
            height: 260,
            child: Padding(
              padding: const EdgeInsets.only(right: 16, top: 12),
              child: LineChart(
                LineChartData(
                  minY: _yMin(hasRange, latestWithRange),
                  maxY: _yMax(hasRange, latestWithRange),
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (v, meta) => Text(
                          v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (v, meta) {
                          final i = v.round();
                          if (i < 0 || i >= values.length) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              DateFormat('MMM').format(values[i].date),
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
                            color: Colors.green.withOpacity(0.5),
                            strokeWidth: 1,
                            dashArray: [6, 4],
                          ),
                          HorizontalLine(
                            y: latestWithRange.refHigh!,
                            color: Colors.green.withOpacity(0.5),
                            strokeWidth: 1,
                            dashArray: [6, 4],
                          ),
                        ])
                      : null,
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots.map((s) {
                        final v = values[s.x.toInt()];
                        return LineTooltipItem(
                          '${DateFormat('d MMM yyyy').format(v.date)}\n${v.value}${unit.isNotEmpty ? ' $unit' : ''}',
                          const TextStyle(color: Colors.white, fontSize: 12),
                        );
                      }).toList(),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (int i = 0; i < values.length; i++)
                          FlSpot(i.toDouble(), values[i].value),
                      ],
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
                            strokeWidth: 0,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (hasRange) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 14, height: 2, color: Colors.green.withOpacity(0.5)),
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
                  '${v.value}${unit.isNotEmpty ? ' $unit' : ''}',
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

  double _yMin(bool hasRange, LabTestValue ref) {
    final dataMin = values.map((v) => v.value).reduce((a, b) => a < b ? a : b);
    final floor = hasRange && ref.refLow! < dataMin ? ref.refLow! : dataMin;
    return floor - (floor.abs() * 0.1 + 1);
  }

  double _yMax(bool hasRange, LabTestValue ref) {
    final dataMax = values.map((v) => v.value).reduce((a, b) => a > b ? a : b);
    final ceil = hasRange && ref.refHigh! > dataMax ? ref.refHigh! : dataMax;
    return ceil + (ceil.abs() * 0.1 + 1);
  }
}

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
        .replaceFirst('{from}', '${result.first.value}${unit.isNotEmpty ? ' $unit' : ''}')
        .replaceFirst('{to}', '${result.latest.value}${unit.isNotEmpty ? ' $unit' : ''}')
        .replaceFirst('{fromDate}', DateFormat('MMM yyyy').format(result.first.date))
        .replaceFirst('{toDate}', DateFormat('MMM yyyy').format(result.latest.date));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
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
