import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import '../models/medicine.dart';
import '../models/appointment.dart';

/// Wraps flutter_local_notifications for two jobs:
/// 1. Medicine reminders (daily or custom weekdays), which ring like an
///    alarm (AndroidScheduleMode.alarmClock) and automatically stop once
///    the medicine's end date passes — no manual cleanup needed.
/// 2. One-off appointment reminders ahead of a doctor's visit, showing
///    the doctor's name directly in the notification title.
///
/// IMPORTANT — what "alarm" means here: AndroidScheduleMode.alarmClock is
/// the closest built-in mechanism in flutter_local_notifications to a real
/// alarm-clock experience (exact-time firing, shows the alarm-clock icon
/// in the status bar, survives Doze/battery optimization). It is not the
/// same as opening a full-screen ringing UI like the stock Clock app —
/// that would require native platform code beyond this package's scope.
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final _plugin = FlutterLocalNotificationsPlugin();

  /// Cap on how many individual occurrences we schedule ahead for a
  /// medicine that has an end date. Keeps things fast and avoids hitting
  /// platform limits on pending exact alarms if someone sets a very long
  /// duration; the reminders simply get topped up again next time the
  /// app is opened (see DatabaseService.getActiveMedicines, which is
  /// called on every screen load).
  static const int _maxBoundedOccurrences = 60;

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

  /// Schedules reminders for a medicine according to its frequency.
  /// - If the medicine has NO end date: schedules an open-ended repeating
  ///   alarm per dose time (daily) or per (dose time, weekday) (custom).
  /// - If it HAS an end date: schedules individual one-time alarms for
  ///   every occurrence between now and the end date, so reminders stop
  ///   exactly on schedule without needing the app to be reopened.
  Future<void> scheduleMedicineReminders(Medicine medicine) async {
    final title = medicine.prescribedBy != null && medicine.prescribedBy!.isNotEmpty
        ? 'Time for your medicine 💊 (Dr. ${medicine.prescribedBy})'
        : 'Time for your medicine 💊';

    for (final time in medicine.times) {
      final parts = time.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      if (medicine.endDate != null) {
        await _scheduleBoundedOccurrences(medicine, time, hour, minute, title);
      } else if (medicine.frequency == MedicineFrequency.daily) {
        await _scheduleOne(
          id: _idFor(medicine.id, time),
          title: title,
          body: '${medicine.name} (${medicine.dosage}) — ${medicine.instructions}',
          scheduledDate: _nextInstanceOfTime(hour, minute),
          matchComponents: DateTimeComponents.time,
          payload: 'medicine:${medicine.id}',
        );
      } else {
        for (final weekday in medicine.customDays) {
          await _scheduleOne(
            id: _idFor(medicine.id, '$time-$weekday'),
            title: title,
            body:
                '${medicine.name} (${medicine.dosage}) — ${medicine.instructions}',
            scheduledDate: _nextInstanceOfWeekdayTime(weekday, hour, minute),
            matchComponents: DateTimeComponents.dayOfWeekAndTime,
            payload: 'medicine:${medicine.id}',
          );
        }
      }
    }
  }

  /// Builds the list of occurrence dates between now and the medicine's
  /// end date (inclusive), respecting daily vs. custom-weekday frequency,
  /// and schedules each as its own one-time alarm with a unique ID.
  Future<void> _scheduleBoundedOccurrences(
      Medicine medicine, String time, int hour, int minute, String title) async {
    final weekdays = medicine.frequency == MedicineFrequency.daily
        ? [1, 2, 3, 4, 5, 6, 7]
        : medicine.customDays;
    if (weekdays.isEmpty) return;

    var cursor = _nextInstanceOfTime(hour, minute);
    var count = 0;
    var occurrenceIndex = 0;

    while (!cursor.isAfter(medicine.endDate!) && count < _maxBoundedOccurrences) {
      if (weekdays.contains(cursor.weekday)) {
        await _scheduleOne(
          id: _idFor(medicine.id, '$time-occurrence-$occurrenceIndex'),
          title: title,
          body: '${medicine.name} (${medicine.dosage}) — ${medicine.instructions}',
          scheduledDate: cursor,
          matchComponents: null, // one-time, no repeat
          payload: 'medicine:${medicine.id}',
        );
        count++;
      }
      occurrenceIndex++;
      cursor = cursor.add(const Duration(days: 1));
    }
  }

  Future<void> _scheduleOne({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required DateTimeComponents? matchComponents,
    required String payload,
  }) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
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
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: matchComponents,
      payload: payload,
    );
  }

  /// Cancels reminders for every scheduling shape a medicine could have
  /// used (open-ended daily, open-ended custom-weekday, or bounded
  /// occurrences) since it may have been edited between those over time.
  Future<void> cancelMedicineReminders(Medicine medicine) async {
    for (final time in medicine.times) {
      await _plugin.cancel(_idFor(medicine.id, time));
      for (var weekday = 1; weekday <= 7; weekday++) {
        await _plugin.cancel(_idFor(medicine.id, '$time-$weekday'));
      }
      for (var i = 0; i < _maxBoundedOccurrences; i++) {
        await _plugin.cancel(_idFor(medicine.id, '$time-occurrence-$i'));
      }
    }
  }

  /// One-time reminder ahead of an appointment (default: 1 hour before).
  /// The doctor's name is in the title itself, not just the body, so it's
  /// visible even in a collapsed notification.
  Future<void> scheduleAppointmentReminder(
    Appointment appt, {
    Duration leadTime = const Duration(hours: 1),
  }) async {
    final fireTime = appt.dateTime.subtract(leadTime);
    if (fireTime.isBefore(DateTime.now())) return; // too late to remind

    await _plugin.zonedSchedule(
      _idFor(appt.id, 'appt'),
      'Appointment with Dr. ${appt.doctorName}',
      '${_formatTime(appt.dateTime)} — ${appt.location}',
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
      androidScheduleMode: AndroidScheduleMode.alarmClock,
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

  /// [weekday] uses DateTime's convention: Monday = 1 ... Sunday = 7.
  tz.TZDateTime _nextInstanceOfWeekdayTime(int weekday, int hour, int minute) {
    var scheduled = _nextInstanceOfTime(hour, minute);
    while (scheduled.weekday != weekday) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
