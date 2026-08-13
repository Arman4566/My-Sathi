import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/appointment.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';
import 'book_by_call_screen.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});
  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  List<Appointment> _appointments = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final appts = await DatabaseService.instance.getUpcomingAppointments();
    setState(() => _appointments = appts);
  }

  /// Shared dialog for both adding a new appointment and editing an
  /// existing one. Pass `existing` to pre-fill the fields for editing.
  Future<void> _showAppointmentDialog({Appointment? existing}) async {
    final lang = context.read<SettingsService>().languageCode;
    final doctorCtrl = TextEditingController(text: existing?.doctorName ?? '');
    final locationCtrl = TextEditingController(text: existing?.location ?? '');
    DateTime? pickedDate = existing?.dateTime;
    TimeOfDay? pickedTime = existing != null
        ? TimeOfDay(hour: existing.dateTime.hour, minute: existing.dateTime.minute)
        : null;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(existing == null
              ? AppText.t('new_appointment', lang)
              : AppText.t('edit_appointment', lang)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: doctorCtrl,
                decoration: InputDecoration(labelText: AppText.t('doctors_name', lang)),
              ),
              TextField(
                controller: locationCtrl,
                decoration: InputDecoration(labelText: AppText.t('location', lang)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: pickedDate ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (d != null) setStateDialog(() => pickedDate = d);
                      },
                      child: Text(pickedDate == null
                          ? AppText.t('pick_date', lang)
                          : '${pickedDate!.day}/${pickedDate!.month}/${pickedDate!.year}'),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: ctx,
                            initialTime: pickedTime ?? TimeOfDay.now());
                        if (t != null) setStateDialog(() => pickedTime = t);
                      },
                      child: Text(pickedTime == null
                          ? AppText.t('pick_time', lang)
                          : pickedTime!.format(ctx)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(AppText.t('cancel', lang))),
            ElevatedButton(
              onPressed: () async {
                if (doctorCtrl.text.isEmpty ||
                    pickedDate == null ||
                    pickedTime == null) {
                  return;
                }

                final dateTime = DateTime(
                  pickedDate!.year,
                  pickedDate!.month,
                  pickedDate!.day,
                  pickedTime!.hour,
                  pickedTime!.minute,
                );

                final appt = Appointment(
                  id: existing?.id ?? const Uuid().v4(),
                  doctorName: doctorCtrl.text,
                  location: locationCtrl.text,
                  dateTime: dateTime,
                );

                // Save the appointment FIRST and unconditionally — reminder
                // scheduling happens after, so a permission problem there
                // can never block saving the appointment itself.
                try {
                  await DatabaseService.instance.insertAppointment(appt);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text(AppText.t('could_not_save', lang).replaceFirst('{error}', '$e'))));
                  }
                  return;
                }

                if (ctx.mounted) Navigator.pop(ctx);
                _load();

                try {
                  if (existing != null) {
                    await NotificationService.instance
                        .cancelAppointmentReminder(existing);
                  }
                  await NotificationService.instance.scheduleAppointmentReminder(appt);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(AppText.t('saved_reminder_failed', lang)),
                      duration: const Duration(seconds: 5),
                    ));
                  }
                }
              },
              child: Text(AppText.t('save', lang)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAppointment(Appointment a) async {
    final lang = context.read<SettingsService>().languageCode;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppText.t('delete_appointment_q', lang)),
        content: Text(AppText.t('delete_appointment_body', lang)
            .replaceFirst('{doctor}', a.doctorName)
            .replaceFirst('{date}',
                '${a.dateTime.day}/${a.dateTime.month}/${a.dateTime.year}')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppText.t('cancel', lang))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppText.t('delete', lang),
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await NotificationService.instance.cancelAppointmentReminder(a);
    await DatabaseService.instance.deleteAppointment(a.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().languageCode;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppText.t('appointments', lang)),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            tooltip: 'Book by AI phone call',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BookByCallScreen()),
              );
              _load();
            },
          ),
        ],
      ),
      body: _appointments.isEmpty
          ? Center(child: Text(AppText.t('no_upcoming_appointments', lang)))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _appointments.length,
              itemBuilder: (context, i) {
                final a = _appointments[i];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.event, color: Color(0xFF5B7CFA)),
                    title: Text('Dr. ${a.doctorName}'),
                    subtitle: Text(
                        '${a.location}\n${a.dateTime.day}/${a.dateTime.month}/${a.dateTime.year} at '
                        '${a.dateTime.hour.toString().padLeft(2, '0')}:${a.dateTime.minute.toString().padLeft(2, '0')}'),
                    isThreeLine: true,
                    onTap: () => _showAppointmentDialog(existing: a),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          tooltip: AppText.t('edit', lang),
                          onPressed: () => _showAppointmentDialog(existing: a),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: Colors.redAccent),
                          tooltip: AppText.t('delete', lang),
                          onPressed: () => _deleteAppointment(a),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAppointmentDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
