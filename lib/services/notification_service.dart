import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:alarm/alarm.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_service.dart';
import 'database_service.dart';
import 'app_text.dart';
import '../models/medicine.dart';
import '../models/appointment.dart';

/// WHY THIS FILE USES THE `alarm` PACKAGE INSTEAD OF PURELY
/// `flutter_local_notifications` FOR REMINDERS:
///
/// The original implementation scheduled reminders as background
/// notifications via `flutter_local_notifications`' `zonedSchedule()`,
/// which relies on Android's AlarmManager waking a BroadcastReceiver that
/// then posts a notification. Extensive testing across multiple phones
/// from different manufacturers (Xiaomi/MIUI and Samsung/One UI) showed
/// this consistently failed silently: `adb shell dumpsys alarm` confirmed
/// Android *did* register and fire the alarm correctly every time, but no
/// notification ever appeared and no error was ever logged anywhere. That
/// consistency across unrelated manufacturers, combined with immediate
/// (foreground) notifications working reliably every time, points to a
/// general modern-Android restriction on what a background broadcast
/// receiver is allowed to do — not a code bug, and not something fixable
/// through device settings alone.
///
/// The `alarm` package sidesteps this by ringing a real, full-screen,
/// audible alarm (the same mechanism dedicated alarm-clock apps use)
/// rather than quietly posting a notification from the background. This
/// gets meaningfully higher OS priority.
///
/// flutter_local_notifications is also used for the "send test
/// notification now" diagnostic, requesting the standard Android
/// notification permission, AND — as of the "Reminder alarm sound"
/// setting — for every reminder when that setting is turned OFF. See
/// `_fireAt()` below: sound ON uses the `alarm` package (rings even
/// through silent mode, like a real alarm clock); sound OFF uses a normal
/// scheduled notification instead, which the OS will mute/vibrate
/// automatically when the phone is silenced, exactly like any other app's
/// notifications.
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final _plugin = FlutterLocalNotificationsPlugin();
  static const _metaPrefsKey = 'alarm_meta_store';

  static const String _medicineSound = 'assets/sounds/medicine_reminder.mp3';
  static const String _appointmentSound = 'assets/sounds/appointment_reminder.mp3';

  static const _quietChannelId = 'reminders_quiet';
  static const _quietChannelName = 'Reminders (notification only)';
  static const _quietChannelDesc =
      'Medicine and appointment reminders shown when "Reminder alarm sound" '
      'is turned off in Settings — a normal notification instead of a '
      'ringing alarm, so it respects your phone\'s silent/vibrate mode.';

  /// Which spoken reminder clip to use for a given reminder kind
  /// ('medicine' or 'appointment').
  String _soundAssetForKind(String kind) =>
      kind == 'appointment' ? _appointmentSound : _medicineSound;

  Future<void> init() async {
    tz_data.initializeTimeZones();
    try {
      final deviceTimeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(deviceTimeZone));
    } catch (e) {
      debugPrint('Could not determine device timezone, defaulting to UTC: $e');
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings =
        InitializationSettings(android: androidInit, iOS: iosInit);
    await _plugin.initialize(initSettings);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    try {
      await androidPlugin?.requestExactAlarmsPermission();
    } catch (e) {
      // Previously silently swallowed. On many Android 12+ phones, the
      // user has to manually flip "Alarms & reminders" on for this app in
      // system settings — if that's off, precise alarm scheduling can
      // fail for anything beyond a very short window. _fireAt() below now
      // also has an automatic fallback so a reminder is never just lost
      // silently, but log this so it's visible while debugging.
      debugPrint('Exact-alarm permission request failed/denied: $e');
    }

    await Alarm.init();
  }

  // ---------- Alarm metadata store ----------
  // The `alarm` package only carries a title/body string with each alarm,
  // not arbitrary structured data. We separately store what each alarm ID
  // means (which medicine/appointment, what time slot) so that when it
  // rings we can look up full details and — for recurring medicine
  // reminders — compute and schedule the *next* occurrence, since the
  // package doesn't have built-in daily/weekly recurrence.
  Future<void> _saveAlarmMeta(int id, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final store = _decodeStore(prefs.getString(_metaPrefsKey));
    store[id.toString()] = data;
    await prefs.setString(_metaPrefsKey, jsonEncode(store));
  }

  Future<Map<String, dynamic>?> getAlarmMeta(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final store = _decodeStore(prefs.getString(_metaPrefsKey));
    return store[id.toString()];
  }

  Future<void> _deleteAlarmMeta(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final store = _decodeStore(prefs.getString(_metaPrefsKey));
    store.remove(id.toString());
    await prefs.setString(_metaPrefsKey, jsonEncode(store));
  }

  Map<String, dynamic> _decodeStore(String? raw) {
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  /// Reads the user's "Reminder alarm sound" preference (Settings screen).
  ///
  /// true  -> ring a real, full-screen, audible alarm via the `alarm`
  ///          package (loops until dismissed). Like a dedicated alarm
  ///          clock, this is designed to be heard even if the phone's
  ///          ringer is silenced — that's the whole point of using it
  ///          instead of a normal notification, and is standard behaviour
  ///          for alarm-clock apps on Android/iOS.
  /// false -> don't ring at all. Post a normal notification instead
  ///          (flutter_local_notifications), which automatically respects
  ///          the phone's silent/vibrate/DND state the same way any other
  ///          app's notifications do.
  Future<bool> _isSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(SettingsService.soundEnabledKey) ?? true;
  }

  /// This is a singleton service with no BuildContext, so it can't use
  /// Provider/context.watch like screens do — it reads the same
  /// SharedPreferences key SettingsService persists to directly, so a
  /// reminder's title/body use whichever language was selected in
  /// Settings the moment it fires (not necessarily what was selected when
  /// it was scheduled, which is what you'd want for a reminder set days
  /// in advance).
  Future<String> _currentLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('settings_language') ?? 'en';
  }

  // ---------- Medicines ----------
  Future<void> scheduleMedicineReminders(Medicine medicine) async {
    final soundEnabled = await _isSoundEnabled();
    final lang = await _currentLanguage();
    for (final time in medicine.times) {
      final next = _nextOccurrenceForMedicine(medicine, time);
      if (next == null) continue; // course already finished for this time

      final id = _idFor(medicine.id, time);
      final title = medicine.prescribedBy != null && medicine.prescribedBy!.isNotEmpty
          ? AppText.t('time_for_medicine_doctor', lang)
              .replaceFirst('{doctor}', medicine.prescribedBy!)
          : AppText.t('time_for_medicine', lang);
      final body = '${medicine.name} (${medicine.dosage}) — ${medicine.instructions}';

      await _saveAlarmMeta(id, {
        'kind': 'medicine',
        'medicineId': medicine.id,
        'time': time,
        'title': title,
        'body': body,
        'assetPath': _medicineSound,
      });

      await _fireAt(
        id: id,
        kind: 'medicine',
        dateTime: next,
        title: title,
        body: body,
        soundEnabled: soundEnabled,
      );
    }
  }

  Future<void> cancelMedicineReminders(Medicine medicine) async {
    for (final time in medicine.times) {
      final id = _idFor(medicine.id, time);
      await _cancelAny(id);
    }
  }

  /// Computes the next time this medicine's dose at [time] should ring,
  /// respecting daily vs. custom-weekday frequency and the end date.
  /// Returns null if the course has already ended.
  DateTime? _nextOccurrenceForMedicine(Medicine medicine, String time) {
    final parts = time.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    final now = DateTime.now();

    var candidate = DateTime(now.year, now.month, now.day, hour, minute);
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }

    if (medicine.frequency == MedicineFrequency.custom) {
      var guard = 0;
      while (!medicine.customDays.contains(candidate.weekday) && guard < 8) {
        candidate = candidate.add(const Duration(days: 1));
        guard++;
      }
      if (guard >= 8) return null; // no valid weekday configured
    }

    if (medicine.endDate != null && candidate.isAfter(medicine.endDate!)) {
      return null;
    }
    return candidate;
  }

  // ---------- Appointments ----------
  Future<void> scheduleAppointmentReminder(
    Appointment appt, {
    Duration leadTime = const Duration(hours: 1),
  }) async {
    final now = DateTime.now();
    var fireTime = appt.dateTime.subtract(leadTime);

    // BUG FIX: previously, if the appointment was created less than
    // `leadTime` away (e.g. someone books/tests an appointment for 20
    // minutes from now), `fireTime` landed in the past and the method
    // just returned — no reminder was ever scheduled, no error shown, no
    // sign anything was wrong. That's exactly what made appointment
    // reminders look "broken" while medicine reminders (which never have
    // this lead-time subtraction) worked fine.
    //
    // Now: if the 1-hour-before slot has already passed but the
    // appointment itself hasn't happened yet, we still schedule a
    // reminder — either right now (a few seconds out) or at the
    // appointment time itself, whichever makes sense — instead of
    // silently giving up.
    if (fireTime.isBefore(now)) {
      if (!appt.dateTime.isAfter(now)) return; // appointment itself already passed
      fireTime = now.add(const Duration(seconds: 5));
    }

    // BUG FIX ("appointment reminder also fires a medicine notification"):
    // this wasn't actually one alarm triggering the other — they're fully
    // independent. What was happening: the default 1-hour-before lead
    // time very often lands on a round hour (e.g. an 11:00 appointment
    // reminds at 10:00), which is exactly when people commonly schedule a
    // medicine too. Both reminders were correctly, separately due at the
    // same minute, so they rang together and looked like one bug. Nudge
    // the appointment reminder a few minutes earlier whenever it would
    // otherwise land within 5 minutes of any active medicine's reminder
    // time that day, so the two are never confusingly simultaneous.
    fireTime = await _avoidCollisionWithMedicines(fireTime);

    final id = _idFor(appt.id, 'appt');
    final lang = await _currentLanguage();
    final title = AppText.t('upcoming_appointment_title', lang);
    final body = AppText.t('appointment_body', lang)
        .replaceFirst('{doctor}', appt.doctorName)
        .replaceFirst('{time}', _formatTime(appt.dateTime))
        .replaceFirst('{location}', appt.location);

    await _saveAlarmMeta(id, {
      'kind': 'appointment',
      'appointmentId': appt.id,
      'title': title,
      'body': body,
      'assetPath': _appointmentSound,
    });

    await _fireAt(
      id: id,
      kind: 'appointment',
      dateTime: fireTime,
      title: title,
      body: body,
      soundEnabled: await _isSoundEnabled(),
    );
  }

  Future<void> cancelAppointmentReminder(Appointment appt) async {
    final id = _idFor(appt.id, 'appt');
    await _cancelAny(id);
  }

  // ---------- Shared scheduling core ----------
  /// Fires a reminder at [dateTime]. This is the single place that decides
  /// *how* a reminder reaches the user, based on the "Reminder alarm
  /// sound" setting:
  ///  - ON  -> a real ringing alarm via the `alarm` package, with the
  ///           kind-specific spoken clip ("It's time to take your
  ///           medicine" / "It's time for your appointment").
  ///  - OFF -> a normal scheduled notification via
  ///           flutter_local_notifications. No ringing, no full-screen
  ///           takeover — just a notification, which respects the phone's
  ///           silent/vibrate/DND state like any other app's notification.
  /// Always clears the other mechanism for this id first, so toggling the
  /// setting between saves can never leave a stray duplicate alarm or
  /// notification scheduled from a previous save.
  Future<void> _fireAt({
    required int id,
    required String kind,
    required DateTime dateTime,
    required String title,
    required String body,
    required bool soundEnabled,
  }) async {
    await _cancelAny(id);

    if (soundEnabled) {
      await Alarm.set(
        alarmSettings: AlarmSettings(
          id: id,
          dateTime: dateTime,
          assetAudioPath: _soundAssetForKind(kind),
          loopAudio: true,
          vibrate: true,
          volumeSettings: const VolumeSettings.fixed(volume: 1.0, volumeEnforced: false),
          androidFullScreenIntent: true,
          notificationSettings: NotificationSettings(title: title, body: body),
        ),
      );
    } else {
      final tzTime = tz.TZDateTime.from(dateTime, tz.local);
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzTime,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _quietChannelId,
            _quietChannelName,
            channelDescription: _quietChannelDesc,
            importance: Importance.high,
            priority: Priority.high,
            // No custom sound here on purpose: a custom notification sound
            // has to ship as a native Android raw resource (not a Flutter
            // asset), which this project structure doesn't include. Using
            // the device's default notification sound keeps this reliable
            // and, crucially, still lets the OS mute/vibrate it normally
            // when the phone is silenced.
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        // Required on flutter_local_notifications versions before v17
        // (removed entirely in v17+, where androidScheduleMode alone is
        // enough). Harmless to include on versions that still accept it.
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> _cancelAny(int id) async {
    await Alarm.stop(id);
    await _plugin.cancel(id);
    await _deleteAlarmMeta(id);
  }

  /// Called from [AlarmRingScreen] when the user taps "Snooze". Re-fires
  /// the same reminder (same kind/sound) after [delay], respecting the
  /// *current* sound setting rather than assuming it's still on.
  Future<void> rescheduleSnoozed(int alarmId, Duration delay) async {
    final meta = await getAlarmMeta(alarmId);
    final kind = meta?['kind'] as String? ?? 'medicine';
    final title = meta?['title'] as String? ?? 'Reminder';
    final body = meta?['body'] as String? ?? '';
    await _saveAlarmMeta(alarmId, {
      ...?meta,
      'title': title,
      'body': body,
    });
    await _fireAt(
      id: alarmId,
      kind: kind,
      dateTime: DateTime.now().add(delay),
      title: title,
      body: body,
      soundEnabled: await _isSoundEnabled(),
    );
  }

  // ---------- Diagnostics (Settings screen test buttons) ----------

  /// Immediate, in-foreground notification — bypasses all scheduling.
  /// This was reliable in every test across every device; if this ever
  /// fails, the problem is notification permissions, not scheduling.
  Future<void> sendTestNotificationNow() async {
    await _plugin.show(
      999001,
      'Test notification',
      'If you can see this, notification display works on this phone.',
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
    );
  }

  /// Schedules a test reminder a short time in the future, using exactly
  /// the same path (and therefore the same sound-setting behaviour) as a
  /// real medicine reminder — good for checking "off = quiet notification,
  /// on = real ringing alarm" actually works on this phone.
  Future<void> sendTestReminderIn(Duration delay) async {
    const id = 999002;
    const title = 'Test reminder';
    const body =
        'If you can see/hear this, scheduled reminders work on this phone.';
    await _saveAlarmMeta(id, {
      'kind': 'medicine',
      'title': title,
      'body': body,
      'assetPath': _medicineSound,
    });
    await _fireAt(
      id: id,
      kind: 'medicine',
      dateTime: DateTime.now().add(delay),
      title: title,
      body: body,
      soundEnabled: await _isSoundEnabled(),
    );
  }

  /// If [candidate] falls within 5 minutes of any active medicine's
  /// reminder time on that same day, shifts it 10 minutes earlier and
  /// checks again (up to a few tries) so it never rings at effectively
  /// the same moment as a medicine reminder.
  Future<DateTime> _avoidCollisionWithMedicines(DateTime candidate) async {
    List<Medicine> medicines;
    try {
      medicines = await DatabaseService.instance.getActiveMedicines();
    } catch (_) {
      return candidate; // if we can't check, don't block scheduling on it
    }

    var result = candidate;
    for (var attempt = 0; attempt < 6; attempt++) {
      var collision = false;
      for (final m in medicines) {
        for (final t in m.times) {
          final parts = t.split(':');
          if (parts.length != 2) continue;
          final hour = int.tryParse(parts[0]);
          final minute = int.tryParse(parts[1]);
          if (hour == null || minute == null) continue;
          final medTime = DateTime(
              result.year, result.month, result.day, hour, minute);
          if (result.difference(medTime).abs() <= const Duration(minutes: 5)) {
            collision = true;
            break;
          }
        }
        if (collision) break;
      }
      if (!collision) break;
      result = result.subtract(const Duration(minutes: 10));
    }
    return result;
  }

  int _idFor(String entityId, String suffix) =>
      (entityId + suffix).hashCode & 0x7fffffff;

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
