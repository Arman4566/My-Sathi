import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/appointment.dart';
import '../models/appointment_call.dart';
import '../services/appointment_call_service.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

/// Lets the patient enter a doctor's phone number plus a requested
/// date/time, then has the AI place the call and negotiate/confirm the
/// slot. Polls the backend for status while the call is live.
///
/// IMPORTANT, shown to the user in-screen too: this places a REAL phone
/// call through a telephony provider (Twilio) configured on the backend.
/// It only works once that's set up (see backend/.env.example), and
/// every call has a small real-world cost — there's no free way to call
/// an arbitrary phone number.
class BookByCallScreen extends StatefulWidget {
  const BookByCallScreen({super.key});
  @override
  State<BookByCallScreen> createState() => _BookByCallScreenState();
}

class _BookByCallScreenState extends State<BookByCallScreen> {
  final _doctorNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _pickedDate;
  TimeOfDay? _pickedTime;

  bool _starting = false;
  String? _error;
  AppointmentCall? _call;
  Timer? _pollTimer;
  bool _savedToAppointments = false;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _doctorNameCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _pickedDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _pickedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _pickedTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _pickedTime = picked);
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:${t.minute.toString().padLeft(2, '0')} $period';
  }

  Future<void> _startCall() async {
    if (_phoneCtrl.text.trim().isEmpty || _pickedDate == null || _pickedTime == null) {
      setState(() => _error = 'Please enter the doctor\'s phone number and pick a date and time.');
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });

    try {
      final profile = await AuthService.instance.getCurrentProfile();
      final call = await AppointmentCallService.instance.startCall(
        doctorPhone: _phoneCtrl.text.trim(),
        doctorName: _doctorNameCtrl.text.trim().isEmpty ? null : _doctorNameCtrl.text.trim(),
        requestedDate: _formatDate(_pickedDate!),
        requestedTime: _formatTime(_pickedTime!),
        patientName: profile?.name,
        notes: _notesCtrl.text.trim(),
      );
      setState(() => _call = call);
      _startPolling();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _starting = false);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final current = _call;
      if (current == null) return;
      try {
        final updated = await AppointmentCallService.instance.getCall(current.id);
        if (!mounted) return;
        setState(() => _call = updated);
        if (updated.isFinished) _pollTimer?.cancel();
      } catch (_) {
        // transient network hiccup — just try again on the next tick
      }
    });
  }

  Future<void> _cancelCall() async {
    final current = _call;
    if (current == null) return;
    try {
      await AppointmentCallService.instance.cancelCall(current.id);
    } catch (_) {}
    _pollTimer?.cancel();
    try {
      final updated = await AppointmentCallService.instance.getCall(current.id);
      if (mounted) setState(() => _call = updated);
    } catch (_) {}
  }

  Future<void> _saveAsAppointment() async {
    final call = _call;
    if (call == null) return;
    final dateTime = call.confirmedDateTime ?? _combinePickedDateTime();
    if (dateTime == null) return;

    await DatabaseService.instance.insertAppointment(Appointment(
      id: const Uuid().v4(),
      doctorName: call.doctorName ?? _doctorNameCtrl.text.trim(),
      location: call.doctorPhone,
      dateTime: dateTime,
      notes: call.outcomeSummary ?? 'Booked by AI phone call.',
    ));
    if (mounted) setState(() => _savedToAppointments = true);
  }

  DateTime? _combinePickedDateTime() {
    if (_pickedDate == null || _pickedTime == null) return null;
    return DateTime(_pickedDate!.year, _pickedDate!.month, _pickedDate!.day,
        _pickedTime!.hour, _pickedTime!.minute);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'no_answer':
      case 'busy':
      case 'failed':
      case 'canceled':
        return Colors.redAccent;
      default:
        return const Color(0xFF5B7CFA);
    }
  }

  String _statusLabel(AppointmentCall c) {
    switch (c.status) {
      case 'queued':
        return 'Starting the call…';
      case 'ringing':
        return 'Ringing the office…';
      case 'in_progress':
        return 'Call in progress…';
      case 'completed':
        switch (c.outcome) {
          case 'confirmed':
            return 'Appointment confirmed!';
          case 'declined':
            return 'The office couldn\u2019t accommodate this request.';
          case 'needs_followup':
            return 'Needs a follow-up call from you.';
          default:
            return 'Call finished.';
        }
      case 'no_answer':
        return 'No one answered.';
      case 'busy':
        return 'The line was busy.';
      case 'failed':
        return 'The call couldn\u2019t be connected.';
      case 'canceled':
        return 'Call canceled.';
      default:
        return c.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;
    return Scaffold(
      appBar: AppBar(title: const Text('Book by AI Phone Call')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'This places a real phone call to the number you enter. The '
                'assistant identifies itself as an automated caller, never '
                'shares your medicines or health details with the office, '
                'and only asks about scheduling.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 20),
            if (call == null) ...[
              TextField(
                controller: _doctorNameCtrl,
                decoration: const InputDecoration(labelText: 'Doctor\'s name (optional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Doctor\'s office phone number',
                  hintText: '+1 415 555 0100',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(_pickedDate == null
                          ? 'Pick date'
                          : _formatDate(_pickedDate!)),
                      onPressed: _pickDate,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time, size: 18),
                      label: Text(_pickedTime == null
                          ? 'Pick time'
                          : _formatTime(_pickedTime!)),
                      onPressed: _pickTime,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes for scheduling (optional)',
                  hintText: 'e.g. "prefer a morning slot if that one is taken"',
                ),
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: _starting
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.call),
                  label: Text(_starting ? 'Starting…' : 'Call to book'),
                  onPressed: _starting ? null : _startCall,
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(
                      color: _statusColor(call.status),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusLabel(call),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              if (call.outcomeSummary != null) ...[
                const SizedBox(height: 8),
                Text(call.outcomeSummary!, style: const TextStyle(fontSize: 14)),
              ],
              const SizedBox(height: 16),
              if (!call.isFinished)
                OutlinedButton.icon(
                  icon: const Icon(Icons.call_end, color: Colors.redAccent),
                  label: const Text('Cancel call', style: TextStyle(color: Colors.redAccent)),
                  onPressed: _cancelCall,
                ),
              if (call.status == 'completed' && call.outcome == 'confirmed' && !_savedToAppointments)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.event_available),
                      label: const Text('Save to my appointments'),
                      onPressed: _saveAsAppointment,
                    ),
                  ),
                ),
              if (_savedToAppointments)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Saved to your appointments.', style: TextStyle(color: Colors.green)),
                ),
              const SizedBox(height: 24),
              if (call.transcript.isNotEmpty) ...[
                const Text('Call transcript', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...call.transcript.map((t) => Align(
                      alignment: t.role == 'assistant'
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(10),
                        constraints: const BoxConstraints(maxWidth: 320),
                        decoration: BoxDecoration(
                          color: t.role == 'assistant'
                              ? const Color(0xFF5B7CFA).withValues(alpha: 0.12)
                              : Colors.grey.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(t.text, style: const TextStyle(fontSize: 13)),
                      ),
                    )),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
