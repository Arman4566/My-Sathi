import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/lab_value.dart';
import '../services/database_service.dart';
import '../services/lab_trend_analyzer.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';
import 'lab_trend_detail_screen.dart';

/// Entry point for "upload blood reports from Jan, Feb, March... and see
/// whether each value is improving or getting worse". Lists every test
/// that has at least two dated readings (a single reading has nothing to
/// trend against) with its most recent value and direction; tapping one
/// opens the full chart.
class LabTrendsScreen extends StatefulWidget {
  const LabTrendsScreen({super.key});
  @override
  State<LabTrendsScreen> createState() => _LabTrendsScreenState();
}

class _LabTrendsScreenState extends State<LabTrendsScreen> {
  bool _loading = true;
  final Map<String, List<LabTestValue>> _series = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final names = await DatabaseService.instance.getTrendableTestNames();
    final series = <String, List<LabTestValue>>{};
    for (final name in names) {
      series[name] = await DatabaseService.instance.getLabValuesForTest(name);
    }
    if (!mounted) return;
    setState(() {
      _series
        ..clear()
        ..addAll(series);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(AppText.t('lab_trends_title', lang))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _series.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      AppText.t('lab_trends_empty', lang),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).hintColor),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _series.length,
                  itemBuilder: (context, i) {
                    final testName = _series.keys.elementAt(i);
                    final values = _series[testName]!;
                    final result = analyzeLabTrend(values);
                    final latest = values.last;
                    return Card(
                      child: ListTile(
                        leading: _TrendIcon(trend: result.trend),
                        title: Text(testName),
                        subtitle: Text(
                          '${latest.value}${latest.unit.isNotEmpty ? ' ${latest.unit}' : ''}'
                          ' • ${values.length} ${AppText.t('readings_suffix', lang)}',
                        ),
                        trailing: _TrendLabel(trend: result.trend, lang: lang),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LabTrendDetailScreen(
                              testName: testName,
                              values: values,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _TrendIcon extends StatelessWidget {
  final LabTrend trend;
  const _TrendIcon({required this.trend});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    switch (trend) {
      case LabTrend.improving:
        icon = Icons.trending_up;
        color = Colors.green;
        break;
      case LabTrend.worsening:
        icon = Icons.trending_down;
        color = Colors.red;
        break;
      case LabTrend.increasing:
        icon = Icons.trending_up;
        color = Colors.blueGrey;
        break;
      case LabTrend.decreasing:
        icon = Icons.trending_down;
        color = Colors.blueGrey;
        break;
      case LabTrend.stable:
        icon = Icons.trending_flat;
        color = Colors.blueGrey;
        break;
    }
    return CircleAvatar(
      backgroundColor: color.withOpacity(0.15),
      child: Icon(icon, color: color),
    );
  }
}

class _TrendLabel extends StatelessWidget {
  final LabTrend trend;
  final String lang;
  const _TrendLabel({required this.trend, required this.lang});

  @override
  Widget build(BuildContext context) {
    String key;
    Color color;
    switch (trend) {
      case LabTrend.improving:
        key = 'trend_improving';
        color = Colors.green;
        break;
      case LabTrend.worsening:
        key = 'trend_worsening';
        color = Colors.red;
        break;
      case LabTrend.increasing:
        key = 'trend_increasing';
        color = Colors.blueGrey;
        break;
      case LabTrend.decreasing:
        key = 'trend_decreasing';
        color = Colors.blueGrey;
        break;
      case LabTrend.stable:
        key = 'trend_stable';
        color = Colors.blueGrey;
        break;
    }
    return Text(
      AppText.t(key, lang),
      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
    );
  }
}
