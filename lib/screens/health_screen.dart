import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/health_record.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});
  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  List<HealthRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await DatabaseService.instance.getHealthRecords();
    setState(() => _records = records);
  }

  Future<void> _addRecord() async {
    final lang = context.read<SettingsService>().languageCode;
    final weightCtrl = TextEditingController();
    final bpCtrl = TextEditingController();
    final sugarCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppText.t('log_current_health', lang)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: AppText.t('weight_kg_hint', lang)),
              ),
              TextField(
                controller: bpCtrl,
                decoration:
                    InputDecoration(labelText: AppText.t('blood_pressure_hint', lang)),
              ),
              TextField(
                controller: sugarCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: AppText.t('blood_sugar_hint', lang)),
              ),
              TextField(
                controller: notesCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                    labelText: AppText.t('feeling_notes_hint', lang)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(AppText.t('cancel', lang))),
          ElevatedButton(
            onPressed: () async {
              final record = HealthRecord(
                id: const Uuid().v4(),
                date: DateTime.now(),
                weightKg: double.tryParse(weightCtrl.text),
                bloodPressure: bpCtrl.text.trim().isEmpty ? null : bpCtrl.text.trim(),
                sugarLevel: double.tryParse(sugarCtrl.text),
                notes: notesCtrl.text.trim(),
              );
              await DatabaseService.instance.insertHealthRecord(record);
              if (ctx.mounted) Navigator.pop(ctx);
              _load();
            },
            child: Text(AppText.t('save', lang)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(AppText.t('my_health', lang))),
      body: _records.isEmpty
          ? Center(
              child: Text(AppText.t('no_health_records', lang),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).hintColor)))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _records.length,
              itemBuilder: (context, i) {
                final r = _records[i];
                final parts = <String>[];
                if (r.weightKg != null) parts.add('${r.weightKg} kg');
                if (r.bloodPressure != null) {
                  parts.add(AppText.t('bp_label', lang).replaceFirst('{value}', r.bloodPressure!));
                }
                if (r.sugarLevel != null) {
                  parts.add(AppText.t('sugar_label', lang)
                      .replaceFirst('{value}', r.sugarLevel.toString()));
                }

                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.monitor_heart_outlined,
                        color: Color(0xFF5B7CFA)),
                    title: Text(parts.isEmpty ? AppText.t('health_note', lang) : parts.join(' • ')),
                    subtitle: Text(
                        '${r.date.day}/${r.date.month}/${r.date.year}'
                        '${r.notes.isNotEmpty ? '\n${r.notes}' : ''}'),
                    isThreeLine: r.notes.isNotEmpty,
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addRecord,
        child: const Icon(Icons.add),
      ),
    );
  }
}
