import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:alarm/alarm.dart';
import '../services/notification_service.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';

/// Shown full-screen (even over the lock screen, via the manifest's
/// showWhenLocked/turnScreenOn) the moment a reminder alarm rings. This is
/// what makes it feel like a real alarm rather than a quiet notification —
/// the sound loops via the `alarm` package until the user explicitly
/// dismisses or snoozes it here.
class AlarmRingScreen extends StatelessWidget {
  final int alarmId;
  final String title;
  final String body;

  const AlarmRingScreen({
    super.key,
    required this.alarmId,
    required this.title,
    required this.body,
  });

  Future<void> _dismiss(BuildContext context) async {
    await Alarm.stop(alarmId);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _snooze(BuildContext context, Duration duration) async {
    await Alarm.stop(alarmId);
    // Goes through NotificationService so the snoozed reminder keeps the
    // correct kind-specific sound (medicine vs. appointment) and honours
    // whatever the "Reminder alarm sound" setting currently is, instead of
    // always forcing a full-volume alarm.mp3 ring regardless of settings.
    await NotificationService.instance.rescheduleSnoozed(alarmId, duration);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().languageCode;
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return PopScope(
      // Block the back button — an alarm shouldn't be dismissible by
      // accident the way a normal screen is.
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1B2E),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 40),
                Text(timeStr,
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 20,
                        fontWeight: FontWeight.w500)),
                const Spacer(),
                _RingingIcon(),
                const SizedBox(height: 32),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                        ),
                        onPressed: () =>
                            _snooze(context, const Duration(minutes: 5)),
                        child: Text(AppText.t('snooze_5min', lang)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5B7CFA),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                        ),
                        onPressed: () => _dismiss(context),
                        child: Text(AppText.t('dismiss', lang)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Simple pulsing ring icon so the screen visibly signals "this is an
/// alarm going off," not just a static notice.
class _RingingIcon extends StatefulWidget {
  @override
  State<_RingingIcon> createState() => _RingingIconState();
}

class _RingingIconState extends State<_RingingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 0.9, end: 1.1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 120,
        height: 120,
        decoration: const BoxDecoration(
          color: Color(0xFF5B7CFA),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.alarm, color: Colors.white, size: 56),
      ),
    );
  }
}

/// Call this once at app startup (see main.dart) to listen for alarms
/// ringing and push [AlarmRingScreen] on top of whatever's currently
/// showing — including waking the app from a killed/background state.
void listenForRingingAlarms(GlobalKey<NavigatorState> navigatorKey) {
  Alarm.ringing.listen((alarmSet) async {
    for (final alarmSettings in alarmSet.alarms) {
      final meta = await NotificationService.instance.getAlarmMeta(alarmSettings.id);
      final title = meta?['title'] as String? ?? 'Reminder';
      final body = meta?['body'] as String? ?? '';

      // For a recurring medicine reminder, schedule its next occurrence
      // right away — proactively, not only if the user dismisses this one
      // — so the chain can't silently break if the app gets killed while
      // this screen is showing.
      if (meta != null && meta['kind'] == 'medicine') {
        final medicineId = meta['medicineId'] as String?;
        if (medicineId != null) {
          final medicine = await DatabaseService.instance.getMedicineById(medicineId);
          if (medicine != null && medicine.active) {
            await NotificationService.instance.scheduleMedicineReminders(medicine);
          }
        }
      }

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => AlarmRingScreen(
            alarmId: alarmSettings.id,
            title: title,
            body: body,
          ),
          fullscreenDialog: true,
        ),
      );
    }
  });
}
