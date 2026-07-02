import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/medicine.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';

class MedicineListScreen extends StatefulWidget {
  const MedicineListScreen({super.key});
  @override
  State<MedicineListScreen> createState() => _MedicineListScreenState();
}

class _MedicineListScreenState extends State<MedicineListScreen> {
  List<Medicine> _medicines = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final meds = await DatabaseService.instance.getActiveMedicines();
    setState(() => _medicines = meds);
  }

  Future<void> _stopMedicine(Medicine m) async {
    await NotificationService.instance.cancelMedicineReminders(m);
    await DatabaseService.instance.deactivateMedicine(m.id);
    _load();
  }

  /// Lets the patient add a medicine directly, without needing a scanned
  /// prescription. Times are entered as a comma-separated list like
  /// "08:00, 20:00" and picked one at a time with a time picker.
  Future<void> _addMedicineManually() async {
    final nameCtrl = TextEditingController();
    final dosageCtrl = TextEditingController();
    final instructionsCtrl = TextEditingController();
    final List<TimeOfDay> times = [];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Add medicine'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Medicine name'),
                ),
                TextField(
                  controller: dosageCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Dosage (e.g. 500mg)'),
                ),
                TextField(
                  controller: instructionsCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Instructions (e.g. after food)'),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Reminder times',
                      style: Theme.of(ctx).textTheme.labelLarge),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final t in times)
                      Chip(
                        label: Text(t.format(ctx)),
                        onDeleted: () => setStateDialog(() => times.remove(t)),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: const Text('Add time'),
                      onPressed: () async {
                        final picked = await showTimePicker(
                            context: ctx, initialTime: TimeOfDay.now());
                        if (picked != null) {
                          setStateDialog(() => times.add(picked));
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty || times.isEmpty) return;

                final medicine = Medicine(
                  id: const Uuid().v4(),
                  name: nameCtrl.text.trim(),
                  dosage: dosageCtrl.text.trim(),
                  instructions: instructionsCtrl.text.trim(),
                  times: times
                      .map((t) =>
                          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}')
                      .toList(),
                  startDate: DateTime.now(),
                );

                await DatabaseService.instance.insertMedicine(medicine);
                await NotificationService.instance
                    .scheduleMedicineReminders(medicine);

                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My medicines')),
      body: _medicines.isEmpty
          ? const Center(child: Text('No active medicines'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _medicines.length,
              itemBuilder: (context, i) {
                final m = _medicines[i];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.medication, color: Color(0xFF5B7CFA)),
                    title: Text(m.name),
                    subtitle: Text(
                        '${m.dosage} • ${m.instructions}\nReminders: ${m.times.join(", ")}'),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
                      tooltip: 'Stop this medicine',
                      onPressed: () => _stopMedicine(m),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMedicineManually,
        icon: const Icon(Icons.add),
        label: const Text('Add medicine'),
      ),
    );
  }
}
