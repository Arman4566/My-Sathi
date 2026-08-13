import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/medicine.dart';
import '../models/prescription.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/ocr_service.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';

const _weekdayLabels = {
  1: 'Mon',
  2: 'Tue',
  3: 'Wed',
  4: 'Thu',
  5: 'Fri',
  6: 'Sat',
  7: 'Sun',
};

/// Mutable, editable version of a suggestion — the user can adjust every
/// field here before anything is saved or scheduled.
class _EditableSuggestion {
  String name;
  String dosage;
  String instructions;
  List<TimeOfDay> times;
  MedicineFrequency frequency;
  Set<int> customDays;
  DateTime? endDate;

  _EditableSuggestion({
    required this.name,
    required this.dosage,
    required this.instructions,
    required this.times,
  })  : frequency = MedicineFrequency.daily,
        customDays = {},
        endDate = null;
}

class ScanPrescriptionScreen extends StatefulWidget {
  const ScanPrescriptionScreen({super.key});
  @override
  State<ScanPrescriptionScreen> createState() => _ScanPrescriptionScreenState();
}

class _ScanPrescriptionScreenState extends State<ScanPrescriptionScreen> {
  final _ocr = OcrService();
  final _picker = ImagePicker();

  File? _image;
  String _rawText = '';
  List<_EditableSuggestion> _suggestions = [];
  bool _loading = false;
  String? _error;

  Future<void> _pickImage(ImageSource source) async {
    // Previously unguarded: if the camera/gallery permission was denied or
    // picking failed for any other reason, pickImage() throws and this
    // whole method silently died with no image, no error, and no way to
    // reach the "Confirm & save" button — which is exactly what "scanning
    // doesn't add anything" looks like from the outside.
    XFile? picked;
    final lang = context.read<SettingsService>().languageCode;
    try {
      picked = await _picker.pickImage(source: source, imageQuality: 85);
    } catch (e) {
      if (mounted) {
        final sourceLabel = source == ImageSource.camera
            ? AppText.t('camera', lang)
            : AppText.t('gallery', lang);
        setState(() => _error = AppText.t('could_not_open_camera_gallery', lang)
            .replaceFirst('{source}', sourceLabel));
      }
      return;
    }
    if (picked == null) return;

    setState(() {
      _image = File(picked!.path);
      _loading = true;
      _error = null;
      _suggestions = [];
    });

    try {
      // Extract OCR text once and reuse it, instead of scanning the image
      // twice (extractRawText + scanAndParse each used to run OCR
      // separately on the same photo).
      final raw = await _ocr.extractRawText(picked.path);
      final suggestions = await _ocr.scanAndParse(raw);
      setState(() {
        _rawText = raw;
        _suggestions = suggestions
            .map((s) => _EditableSuggestion(
                  name: s.name,
                  dosage: s.dosage,
                  instructions: s.instructions,
                  times: s.suggestedTimes.map((t) {
                    final parts = t.split(':');
                    return TimeOfDay(
                        hour: int.parse(parts[0]), minute: int.parse(parts[1]));
                  }).toList(),
                ))
            .toList();
        if (_suggestions.isEmpty) {
          _error = AppText.t('no_medicines_detected', lang);
        }
      });
    } catch (e) {
      setState(() => _error = AppText.t('could_not_read_prescription', lang));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _editSuggestion(_EditableSuggestion s) async {
    final lang = context.read<SettingsService>().languageCode;
    final nameCtrl = TextEditingController(text: s.name);
    final dosageCtrl = TextEditingController(text: s.dosage);
    final instructionsCtrl = TextEditingController(text: s.instructions);
    final times = List<TimeOfDay>.from(s.times);
    var frequency = s.frequency;
    final customDays = {...s.customDays};
    DateTime? endDate = s.endDate;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(AppText.t('edit_medicine_title', lang)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(labelText: AppText.t('medicine_name_short', lang)),
                ),
                TextField(
                  controller: dosageCtrl,
                  decoration: InputDecoration(labelText: AppText.t('dosage_short', lang)),
                ),
                TextField(
                  controller: instructionsCtrl,
                  decoration: InputDecoration(labelText: AppText.t('instructions_short', lang)),
                ),
                const SizedBox(height: 14),
                Text(AppText.t('reminder_times', lang), style: Theme.of(ctx).textTheme.labelLarge),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in times)
                      Chip(
                        label: Text(t.format(ctx)),
                        onDeleted: () => setStateDialog(() => times.remove(t)),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: Text(AppText.t('add_time', lang)),
                      onPressed: () async {
                        final picked = await showTimePicker(
                            context: ctx, initialTime: TimeOfDay.now());
                        if (picked != null) setStateDialog(() => times.add(picked));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(AppText.t('frequency', lang), style: Theme.of(ctx).textTheme.labelLarge),
                RadioGroup<MedicineFrequency>(
                  groupValue: frequency,
                  onChanged: (v) => setStateDialog(() => frequency = v!),
                  child: Column(
                    children: [
                      RadioListTile<MedicineFrequency>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(AppText.t('every_day', lang)),
                        value: MedicineFrequency.daily,
                      ),
                      RadioListTile<MedicineFrequency>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(AppText.t('custom_days', lang)),
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
                Text(AppText.t('stop_after_optional', lang),
                    style: Theme.of(ctx).textTheme.labelLarge),
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text(endDate == null
                          ? AppText.t('no_end_date', lang)
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
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(AppText.t('cancel', lang))),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  s.name = nameCtrl.text.trim();
                  s.dosage = dosageCtrl.text.trim();
                  s.instructions = instructionsCtrl.text.trim();
                  s.times = times;
                  s.frequency = frequency;
                  s.customDays = customDays;
                  s.endDate = endDate;
                });
                Navigator.pop(ctx);
              },
              child: Text(AppText.t('done', lang)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndSave() async {
    if (_image == null) return;
    final lang = context.read<SettingsService>().languageCode;
    final prescriptionId = const Uuid().v4();
    var reminderFailures = 0;
    var skipped = 0;

    try {
      await DatabaseService.instance.insertPrescription(Prescription(
        id: prescriptionId,
        imagePath: _image!.path,
        rawText: _rawText,
        doctorName: '',
        dateAdded: DateTime.now(),
      ));

      for (final s in _suggestions) {
        // Previously skipped silently — if every suggestion was missing a
        // name or a reminder time, "Confirm & save" appeared to do nothing
        // at all. Now the user is told exactly how many were skipped and
        // why, via the snackbar below.
        if (s.name.trim().isEmpty || s.times.isEmpty) {
          skipped++;
          continue;
        }

        final medicine = Medicine(
          id: const Uuid().v4(),
          name: s.name,
          dosage: s.dosage,
          instructions: s.instructions,
          times: s.times
              .map((t) =>
                  '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}')
              .toList(),
          startDate: DateTime.now(),
          endDate: s.endDate,
          prescriptionId: prescriptionId,
          frequency: s.frequency,
          customDays: s.customDays.toList()..sort(),
        );
        // Save the medicine unconditionally; a reminder-scheduling
        // failure for one medicine shouldn't stop the rest from saving
        // or leave the screen stuck.
        await DatabaseService.instance.insertMedicine(medicine);
        try {
          await NotificationService.instance.scheduleMedicineReminders(medicine);
        } catch (_) {
          reminderFailures++;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppText.t('could_not_save', lang).replaceFirst('{error}', '$e'))));
      }
      return;
    }

    if (mounted) {
      if (skipped > 0 && skipped == _suggestions.length) {
        // Nothing was actually saved — say so clearly instead of just
        // closing the screen as if it worked.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppText.t('nothing_saved_missing_fields', lang)),
          duration: const Duration(seconds: 6),
        ));
        return;
      }
      if (skipped > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppText.t('items_skipped', lang).replaceFirst('{count}', '$skipped')),
          duration: const Duration(seconds: 5),
        ));
      }
      if (reminderFailures > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppText.t('reminders_failed_count', lang)
              .replaceFirst('{count}', '$reminderFailures')),
          duration: const Duration(seconds: 5),
        ));
      }
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _ocr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(AppText.t('scan_prescription', lang))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(_image!, height: 180, fit: BoxFit.cover),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: Text(AppText.t('take_photo', lang)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: Text(AppText.t('from_gallery', lang)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.orange)),
            if (_suggestions.isNotEmpty) ...[
              Text(AppText.t('review_before_saving', lang),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                AppText.t('automatic_reading_note', lang),
                style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: _suggestions.length,
                  itemBuilder: (context, i) {
                    final s = _suggestions[i];
                    final freqLabel = s.frequency == MedicineFrequency.daily
                        ? AppText.t('every_day', lang)
                        : s.customDays.isEmpty
                            ? AppText.t('custom_pick_days', lang)
                            : AppText.t('on_days', lang).replaceFirst('{days}',
                                s.customDays.map((d) => _weekdayLabels[d]).join(", "));
                    return Card(
                      child: ListTile(
                        title: Text(s.name.isEmpty ? AppText.t('name_unclear', lang) : s.name),
                        subtitle: Text(
                            '${s.dosage} • ${s.instructions}\n$freqLabel at ${s.times.map((t) => t.format(context)).join(", ")}'
                            '${s.endDate != null ? AppText.t('until_date', lang).replaceFirst('{date}', '${s.endDate!.day}/${s.endDate!.month}/${s.endDate!.year}') : ""}'),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _editSuggestion(s),
                        ),
                        onTap: () => _editSuggestion(s),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _confirmAndSave,
                child: Text(AppText.t('confirm_and_save', lang)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
