import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/health_record.dart';
import '../services/database_service.dart';

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
    final weightCtrl = TextEditingController();
    final bpCtrl = TextEditingController();
    final sugarCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log current health'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Weight (kg)'),
              ),
              TextField(
                controller: bpCtrl,
                decoration:
                    const InputDecoration(labelText: 'Blood pressure (e.g. 120/80)'),
              ),
              TextField(
                controller: sugarCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Blood sugar (mg/dL)'),
              ),
              TextField(
                controller: notesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'How are you feeling? (notes)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My health')),
      body: _records.isEmpty
          ? Center(
              child: Text('No health records yet.\nTap + to log how you feel today.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).hintColor)))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _records.length,
              itemBuilder: (context, i) {
                final r = _records[i];
                final parts = <String>[];
                if (r.weightKg != null) parts.add('${r.weightKg} kg');
                if (r.bloodPressure != null) parts.add('BP ${r.bloodPressure}');
                if (r.sugarLevel != null) parts.add('Sugar ${r.sugarLevel} mg/dL');

                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.monitor_heart_outlined,
                        color: Color(0xFF5B7CFA)),
                    title: Text(parts.isEmpty ? 'Health note' : parts.join(' • ')),
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
