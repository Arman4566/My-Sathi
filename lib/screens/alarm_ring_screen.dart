import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:alarm/alarm.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';
import '../services/app_text.dart';

/// Shown full-screen (even over the lock screen, via the manifest's
/// showWhenLocked/turnScreenOn) the moment a reminder alarm rings. This is
/// what makes it feel like a real alarm rather than a quiet notification —
/// the sound loops via the `alarm` package until the user explicitly
/// dismisses or snoozes it here.
class AlarmRingScreen extends StatefulWidget {
  final int alarmId;
  final String title;
  final String body;
  // Only set for kind == 'medicine' — lets this screen offer an explicit
  // "I took it ✅" confirmation instead of just Snooze/Dismiss, and know
  // which medicine(s) + which scheduled slot to record it against (a
  // slot can cover more than one medicine if their times clashed — see
  // NotificationService._recomputeMedicineAlarms).
  final List<String>? medicineIds;
  final DateTime? scheduledFor;

  const AlarmRingScreen({
    super.key,
    required this.alarmId,
    required this.title,
    required this.body,
    this.medicineIds,
    this.scheduledFor,
  });

  @override
  State<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends State<AlarmRingScreen> {
  bool _confirming = false;

  Future<void> _dismiss() async {
    await Alarm.stop(widget.alarmId);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _snooze(Duration duration) async {
    await Alarm.stop(widget.alarmId);
    // Goes through NotificationService so the snoozed reminder keeps the
    // correct kind-specific sound (medicine vs. appointment) and honours
    // whatever the "Reminder alarm sound" setting currently is, instead of
    // always forcing a full-volume alarm.mp3 ring regardless of settings.
    await NotificationService.instance.rescheduleSnoozed(widget.alarmId, duration);
    if (mounted) Navigator.of(context).pop();
  }

  /// Records "taken" for every medicine in this slot (usually one, more
  /// if two+ medicines clashed at the same time), pushes that to the
  /// backend so the missed-dose WhatsApp poller leaves it alone, then
  /// dismisses the alarm same as a normal Dismiss would.
  Future<void> _confirmTaken() async {
    final ids = widget.medicineIds;
    final scheduledFor = widget.scheduledFor;
    if (ids == null || ids.isEmpty || scheduledFor == null) {
      await _dismiss();
      return;
    }
    setState(() => _confirming = true);
    try {
      for (final id in ids) {
        await DatabaseService.instance.markDoseTaken(id, scheduledFor);
      }
    } finally {
      await _dismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().languageCode;
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final canConfirmTaken = widget.medicineIds != null && widget.medicineIds!.isNotEmpty;

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
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const Spacer(),
                if (canConfirmTaken) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3DBE7A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      icon: _confirming
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_outline),
                      onPressed: _confirming ? null : _confirmTaken,
                      label: Text(AppText.t('i_took_it', lang)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
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
                        onPressed: _confirming ? null : () => _snooze(const Duration(minutes: 5)),
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
                        onPressed: _confirming ? null : _dismiss,
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

      // For a recurring medicine reminder, schedule the next occurrence(s)
      // right away — proactively, not only if the user dismisses this one
      // — so the chain can't silently break if the app gets killed while
      // this screen is showing. A slot can now represent more than one
      // medicine (see NotificationService._recomputeMedicineAlarms, which
      // merges medicines clashing at the same moment into one alarm), so
      // this recomputes every active medicine's next slot in one pass
      // rather than assuming a single medicine id.
      if (meta != null && meta['kind'] == 'medicine') {
        await NotificationService.instance.recomputeAllMedicineAlarms();
      }

      final medicineIds = (meta?['medicineIds'] as List?)?.map((e) => e.toString()).toList();
      final scheduledFor = meta?['scheduledFor'] != null
          ? DateTime.tryParse(meta!['scheduledFor'] as String)
          : null;

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => AlarmRingScreen(
            alarmId: alarmSettings.id,
            title: title,
            body: body,
            medicineIds: medicineIds,
            scheduledFor: scheduledFor,
          ),
          fullscreenDialog: true,
        ),
      );
    }
  });
}
