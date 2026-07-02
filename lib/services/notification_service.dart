import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import '../models/medicine.dart';
import '../models/appointment.dart';

/// Wraps flutter_local_notifications for two jobs:
/// 1. Daily repeating medicine reminders (e.g. every day at 08:00, 20:00)
/// 2. One-off appointment reminders (e.g. 1 hour before the visit)
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz_data.initializeTimeZones();
    // If you need the DEVICE's real timezone (not just UTC), pair this with
    // the `flutter_timezone` package to call tz.setLocalLocation(...).

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings =
        InitializationSettings(android: androidInit, iOS: iosInit);

    await _plugin.initialize(initSettings);

    // Android 13+ requires runtime notification permission.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Schedules one repeating daily notification per dose time in the medicine.
  /// Each (medicine, time-of-day) pair gets a stable, deterministic ID so
  /// re-scheduling or cancelling later is reliable.
  Future<void> scheduleMedicineReminders(Medicine medicine) async {
    for (final time in medicine.times) {
      final parts = time.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      final id = _idFor(medicine.id, time);
      final scheduledDate = _nextInstanceOfTime(hour, minute);

      await _plugin.zonedSchedule(
        id,
        'Time for your medicine 💊',
        '${medicine.name} (${medicine.dosage}) — ${medicine.instructions}',
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'medicine_reminders',
            'Medicine Reminders',
            channelDescription: 'Reminders to take scheduled medicine',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time, // repeats daily
        payload: 'medicine:${medicine.id}',
      );
    }
  }

  Future<void> cancelMedicineReminders(Medicine medicine) async {
    for (final time in medicine.times) {
      await _plugin.cancel(_idFor(medicine.id, time));
    }
  }

  /// One-time reminder ahead of an appointment (default: 1 hour before).
  Future<void> scheduleAppointmentReminder(
    Appointment appt, {
    Duration leadTime = const Duration(hours: 1),
  }) async {
    final fireTime = appt.dateTime.subtract(leadTime);
    if (fireTime.isBefore(DateTime.now())) return; // too late to remind

    await _plugin.zonedSchedule(
      _idFor(appt.id, 'appt'),
      'Upcoming appointment',
      'Dr. ${appt.doctorName} at ${_formatTime(appt.dateTime)} — ${appt.location}',
      tz.TZDateTime.from(fireTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'appointment_reminders',
          'Appointment Reminders',
          channelDescription: 'Reminders about upcoming doctor appointments',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'appointment:${appt.id}',
    );
  }

  Future<void> cancelAppointmentReminder(Appointment appt) async {
    await _plugin.cancel(_idFor(appt.id, 'appt'));
  }

  int _idFor(String entityId, String suffix) =>
      (entityId + suffix).hashCode & 0x7fffffff;

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
