import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/medicine.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';

const _weekdayLabels = {
  1: 'Mon',
  2: 'Tue',
  3: 'Wed',
  4: 'Thu',
  5: 'Fri',
  6: 'Sat',
  7: 'Sun',
};

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

  Future<void> _deleteMedicine(Medicine m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete medicine?'),
        content: Text(
            'This permanently removes "${m.name}" and its reminders. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await NotificationService.instance.cancelMedicineReminders(m);
    await DatabaseService.instance.deleteMedicine(m.id);
    _load();
  }

  /// Shared dialog for adding a new medicine and editing an existing one.
  Future<void> _showMedicineDialog({Medicine? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final dosageCtrl = TextEditingController(text: existing?.dosage ?? '');
    final instructionsCtrl =
        TextEditingController(text: existing?.instructions ?? '');
    final List<TimeOfDay> times = existing != null
        ? existing.times.map((t) {
            final parts = t.split(':');
            return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
          }).toList()
        : [];
    MedicineFrequency frequency = existing?.frequency ?? MedicineFrequency.daily;
    final Set<int> customDays = {...(existing?.customDays ?? [])};
    DateTime? endDate = existing?.endDate;
    String? photoPath = existing?.photoPath;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(existing == null ? 'Add medicine' : 'Edit medicine'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: photoPath != null && File(photoPath!).existsSync()
                            ? Image.file(File(photoPath!),
                                width: 90, height: 90, fit: BoxFit.cover)
                            : Container(
                                width: 90,
                                height: 90,
                                color: Theme.of(ctx).colorScheme.primaryContainer,
                                child: Icon(Icons.medication,
                                    color: Theme.of(ctx).colorScheme.primary, size: 36),
                              ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: InkWell(
                          onTap: () async {
                            final picked = await ImagePicker().pickImage(
                                source: ImageSource.camera, imageQuality: 85);
                            if (picked != null) {
                              setStateDialog(() => photoPath = picked.path);
                            }
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Color(0xFF5B7CFA),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
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
                const SizedBox(height: 14),
                Text('Reminder times', style: Theme.of(ctx).textTheme.labelLarge),
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
                const SizedBox(height: 14),
                Text('Frequency', style: Theme.of(ctx).textTheme.labelLarge),
                RadioGroup<MedicineFrequency>(
                  groupValue: frequency,
                  onChanged: (v) => setStateDialog(() => frequency = v!),
                  child: const Column(
                    children: [
                      RadioListTile<MedicineFrequency>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text('Every day'),
                        value: MedicineFrequency.daily,
                      ),
                      RadioListTile<MedicineFrequency>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text('Custom days'),
                        value: MedicineFrequency.custom,
                      ),
                    ],
                  ),
                ),
                if (frequency == MedicineFrequency.custom)
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final day in _weekdayLabels.keys)
                        FilterChip(
                          label: Text(_weekdayLabels[day]!),
                          selected: customDays.contains(day),
                          onSelected: (sel) => setStateDialog(() {
                            if (sel) {
                              customDays.add(day);
                            } else {
                              customDays.remove(day);
                            }
                          }),
                        ),
                    ],
                  ),
                const SizedBox(height: 14),
                Text('Stop after (optional)',
                    style: Theme.of(ctx).textTheme.labelLarge),
                const SizedBox(height: 6),
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text(endDate == null
                          ? 'No end date — ongoing'
                          : '${endDate!.day}/${endDate!.month}/${endDate!.year}'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now().add(const Duration(days: 7)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 3650)),
                        );
                        if (picked != null) setStateDialog(() => endDate = picked);
                      },
                    ),
                    if (endDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setStateDialog(() => endDate = null),
                      ),
                  ],
                ),
                Text(
                  'When an end date passes, this medicine is automatically '
                  'stopped and its reminders removed.',
                  style: TextStyle(color: Theme.of(ctx).hintColor, fontSize: 12),
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
                if (frequency == MedicineFrequency.custom && customDays.isEmpty) {
                  return;
                }

                final medicine = Medicine(
                  id: existing?.id ?? const Uuid().v4(),
                  name: nameCtrl.text.trim(),
                  dosage: dosageCtrl.text.trim(),
                  instructions: instructionsCtrl.text.trim(),
                  times: times
                      .map((t) =>
                          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}')
                      .toList(),
                  startDate: existing?.startDate ?? DateTime.now(),
                  endDate: endDate,
                  frequency: frequency,
                  customDays: customDays.toList()..sort(),
                  photoPath: photoPath,
                );

                // Save the medicine itself FIRST and unconditionally. Reminder
                // scheduling is handled separately below so that a permission
                // problem or other notification error can never block saving
                // your data or leave the dialog stuck open with no feedback.
                try {
                  if (existing != null) {
                    await DatabaseService.instance.updateMedicine(medicine);
                  } else {
                    await DatabaseService.instance.insertMedicine(medicine);
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('Could not save: $e')));
                  }
                  return; // don't close the dialog if the save itself failed
                }

                if (ctx.mounted) Navigator.pop(ctx);
                _load();

                // Reminder scheduling happens after the dialog closes, so a
                // failure here (e.g. exact-alarm permission not granted)
                // only shows a warning — it never prevents the medicine
                // itself from being saved.
                try {
                  if (existing != null) {
                    await NotificationService.instance
                        .cancelMedicineReminders(existing);
                  }
                  await NotificationService.instance
                      .scheduleMedicineReminders(medicine);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          'Saved, but reminders could not be scheduled. '
                          'Check notification/alarm permissions in phone settings.'),
                      duration: Duration(seconds: 5),
                    ));
                  }
                }
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
                final freqLabel = m.frequency == MedicineFrequency.daily
                    ? 'Every day'
                    : 'On ${m.customDays.map((d) => _weekdayLabels[d]).join(", ")}';
                final endLabel = m.endDate != null
                    ? ' • until ${m.endDate!.day}/${m.endDate!.month}/${m.endDate!.year}'
                    : '';

                return Card(
                  child: ListTile(
                    leading: (m.photoPath != null && File(m.photoPath!).existsSync())
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(File(m.photoPath!),
                                width: 44, height: 44, fit: BoxFit.cover),
                          )
                        : const Icon(Icons.medication, color: Color(0xFF5B7CFA)),
                    title: Text(m.name),
                    subtitle: Text(
                        '${m.dosage} • ${m.instructions}\n$freqLabel at ${m.times.join(", ")}$endLabel'),
                    isThreeLine: true,
                    onTap: () => _showMedicineDialog(existing: m),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          tooltip: 'Edit',
                          onPressed: () => _showMedicineDialog(existing: m),
                        ),
                        IconButton(
                          icon: const Icon(Icons.stop_circle_outlined, size: 20),
                          tooltip: 'Stop (keep in history)',
                          onPressed: () => _stopMedicine(m),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: Colors.redAccent),
                          tooltip: 'Delete permanently',
                          onPressed: () => _deleteMedicine(m),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showMedicineDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add medicine'),
      ),
    );
  }
}
