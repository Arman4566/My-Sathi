import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:uuid/uuid.dart';
import '../models/medicine.dart';
import '../models/appointment.dart';
import '../models/medical_report.dart';
import '../models/prescription.dart';
import '../widgets/fullscreen_image_viewer.dart';
import 'report_detail_screen.dart';
import 'prescription_detail_screen.dart';
import '../services/ai_backend_service.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';

class _ChatMessage {
  final String text;
  final bool fromUser;
  final ChatAction? action;
  bool actionHandled = false;

  /// Set (possibly empty) when the assistant was asked to find a saved
  /// report/prescription; null for ordinary messages.
  final List<_FoundDoc>? docs;

  _ChatMessage(this.text, this.fromUser, {this.action, this.docs});
}

/// One saved report or prescription matched by a "find my ..." request.
class _FoundDoc {
  final String title;
  final String subtitle;
  final String? filePath; // the scanned photo, if it still exists
  final MedicalReport? report;
  final Prescription? prescription;

  _FoundDoc({
    required this.title,
    required this.subtitle,
    required this.filePath,
    this.report,
    this.prescription,
  });

  bool get isPrescription => prescription != null;
  bool get hasFile => filePath != null && File(filePath!).existsSync();
}

class ChatbotScreen extends StatefulWidget {
  /// If opened from a specific report/prescription, these carry that
  /// context so the assistant can discuss it — e.g. "Scanned report from
  /// 3/7/2026" and the OCR text of that report.
  final String? initialContextLabel;
  final String? initialContextText;

  const ChatbotScreen({
    super.key,
    this.initialContextLabel,
    this.initialContextText,
  });

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _speech = stt.SpeechToText();
  late final List<_ChatMessage> _messages;
  bool _sending = false;
  bool _listening = false;
  bool _speechAvailable = false;

  late String _lang;

  @override
  void initState() {
    super.initState();
    _lang = context.read<SettingsService>().languageCode;
    _messages = [
      _ChatMessage(
        widget.initialContextLabel != null
            ? AppText.t('chat_greeting_context', _lang)
                .replaceFirst('{context}', widget.initialContextLabel!)
            : AppText.t('chat_greeting_default', _lang),
        false,
      ),
    ];
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() => _listening = false);
        }
      },
      onError: (error) => setState(() => _listening = false),
    );
    setState(() => _speechAvailable = available);
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) return;

    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }

    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        setState(() => _controller.text = result.recognizedWords);
        if (result.finalResult) {
          setState(() => _listening = false);
        }
      },
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // Read this before any `await` below — using `context` after an async
    // gap is unsafe if the widget gets unmounted mid-request (analyzer
    // flags this correctly), so grab what we need from it up front.
    final languageCode = context.read<SettingsService>().languageCode;

    setState(() {
      _messages.add(_ChatMessage(text, true));
      _sending = true;
      _controller.clear();
    });

    try {
      // Gather the patient's real data so the assistant can answer from
      // it and (only when explicitly asked) propose adding something.
      final meds = await DatabaseService.instance.getActiveMedicines();
      final appts = await DatabaseService.instance.getUpcomingAppointments();
      final reports = await DatabaseService.instance.getMedicalReports();
      final profile = await AuthService.instance.getCurrentProfile();

      // Recent turns of this conversation (oldest first), excluding the
      // message we just added above (the backend appends that itself as
      // the final turn) — this is what lets the assistant follow up
      // correctly instead of treating every message as a fresh, isolated
      // question with no memory of what was said a moment ago.
      final history = _messages
          .sublist(0, _messages.length - 1)
          .map((m) => {'role': m.fromUser ? 'user' : 'assistant', 'text': m.text})
          .toList();

      final response = await AiBackendService.instance.sendChatMessage(
        message: text,
        history: history,
        medicines: meds
            .map((m) => {
                  'name': m.name,
                  'dosage': m.dosage,
                  'instructions': m.instructions,
                  'times': m.times,
                  'frequency': m.frequency.name,
                  'endDate': m.endDate?.toIso8601String(),
                })
            .toList(),
        appointments: appts
            .map((a) => {
                  'doctorName': a.doctorName,
                  'location': a.location,
                  'dateTime': a.dateTime.toIso8601String(),
                })
            .toList(),
        reports: reports
            .take(5)
            .map((r) => {
                  'title': r.title,
                  'uploadedDate': r.uploadedDate.toIso8601String(),
                  'summary': r.summary,
                })
            .toList(),
        profile: profile == null
            ? null
            : {
                'age': profile.age,
                'weightKg': profile.weightKg,
                'heightCm': profile.heightCm,
                'gender': profile.gender,
              },
        reportContext: widget.initialContextText,
        language: languageCode,
      );

      // Safety net: even though the backend is instructed not to use
      // markdown in the reply, strip common markdown symbols if the model
      // includes them anyway (e.g. **bold**, `code`, bullet dashes) so it
      // never renders as literal asterisks/backticks in the plain-text
      // chat bubble.
      var cleanReply = _stripMarkdown(response.reply);

      // "Not sure" safety net: if the assistant flagged that it wasn't
      // confident, make sure the patient is told to see a doctor even
      // when the model's own wording forgot to say so.
      if (response.uncertain && !_mentionsProfessional(cleanReply)) {
        cleanReply = '$cleanReply\n\n${AppText.t('consult_doctor_note', languageCode)}';
      }

      // "Find my ... report/prescription": searched on this phone (no
      // extra AI call), results shown with View / Download buttons.
      // Not a confirm-card action, so it isn't attached as one.
      List<_FoundDoc>? docs;
      var action = response.action;
      if (action != null && action.type == 'find_documents') {
        docs = await _findDocuments(
          (action.data['kind'] as String?) ?? 'any',
          (action.data['query'] as String?) ?? '',
        );
        action = null;
      }

      setState(() => _messages.add(
          _ChatMessage(cleanReply, false, action: action, docs: docs)));
    } catch (e) {
      final detail = e.toString().replaceFirst('Exception: ', '');
      final isKnownMessage = detail.isNotEmpty && !detail.contains('SocketException') &&
          !detail.startsWith('Chat request failed');
      setState(() => _messages.add(_ChatMessage(
          isKnownMessage
              ? detail
              : "Sorry, I couldn't reach the assistant right now. If this is "
                  "urgent, please contact your doctor or pharmacist directly.",
          false)));
    } finally {
      setState(() => _sending = false);
      await Future.delayed(const Duration(milliseconds: 100));
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  static final _professionalWords = RegExp(
      r'doctor|physician|pharmacist|डॉक्टर|चिकित्सक|फार्मासिस्ट|दवा विक्रेता',
      caseSensitive: false);

  bool _mentionsProfessional(String text) => _professionalWords.hasMatch(text);

  static const _stopWords = {
    'report', 'reports', 'prescription', 'prescriptions', 'my', 'the',
    'of', 'for', 'and', 'a', 'an',
  };

  /// Searches the saved reports/prescriptions on this device. [query] is
  /// a few English keywords from the assistant (a test name, doctor name,
  /// etc.); with no keywords it just returns the newest ones. Best matches
  /// first, then newest. At most 5.
  Future<List<_FoundDoc>> _findDocuments(String kind, String query) async {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9\u0900-\u097F]+'))
        .where((t) => t.length >= 2 && !_stopWords.contains(t))
        .toList();
    final fmt = DateFormat('d MMM yyyy');
    final scored = <MapEntry<_FoundDoc, ({int score, DateTime date})>>[];

    int score(String title, String body) {
      if (terms.isEmpty) return 0;
      final t = title.toLowerCase();
      final b = body.toLowerCase();
      var s = 0;
      for (final term in terms) {
        if (t.contains(term)) s += 3;
        if (b.contains(term)) s += 1;
      }
      return s;
    }

    if (kind != 'prescription') {
      for (final r in await DatabaseService.instance.getMedicalReports()) {
        final sc = score(r.title, '${r.summary} ${r.rawText}');
        if (terms.isNotEmpty && sc == 0) continue;
        scored.add(MapEntry(
          _FoundDoc(
            title: r.title,
            subtitle: '${AppText.t('doc_type_report', _lang)} • ${fmt.format(r.uploadedDate)}',
            filePath: r.filePath,
            report: r,
          ),
          (score: sc, date: r.uploadedDate),
        ));
      }
    }
    if (kind != 'report') {
      for (final p in await DatabaseService.instance.getPrescriptions()) {
        final title = p.doctorName.isNotEmpty
            ? '${AppText.t('doc_type_prescription', _lang)} — Dr. ${p.doctorName}'
            : AppText.t('doc_type_prescription', _lang);
        final sc = score(title, '${p.notes} ${p.rawText}');
        if (terms.isNotEmpty && sc == 0) continue;
        scored.add(MapEntry(
          _FoundDoc(
            title: title,
            subtitle: '${AppText.t('doc_type_prescription', _lang)} • ${fmt.format(p.dateAdded)}',
            filePath: p.imagePath,
            prescription: p,
          ),
          (score: sc, date: p.dateAdded),
        ));
      }
    }

    scored.sort((a, b) {
      final byScore = b.value.score.compareTo(a.value.score);
      return byScore != 0 ? byScore : b.value.date.compareTo(a.value.date);
    });
    return scored.take(5).map((e) => e.key).toList();
  }

  void _viewDoc(_FoundDoc d) {
    if (d.hasFile) {
      FullscreenImageViewer.open(context, File(d.filePath!), title: d.title);
    } else if (d.report != null) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => ReportDetailScreen(report: d.report!)));
    } else if (d.prescription != null) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PrescriptionDetailScreen(prescription: d.prescription!)));
    }
  }

  /// Removes common markdown syntax so a reply never shows literal
  /// asterisks/backticks/heading-hashes if the model slips and includes
  /// them despite being told not to.
  String _stripMarkdown(String text) {
    var out = text;
    out = out.replaceAll(RegExp(r'```[a-zA-Z]*\n?'), '');
    out = out.replaceAll('`', '');
    out = out.replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1');
    out = out.replaceAll(RegExp(r'(?<!\*)\*(?!\*)(.+?)\*(?!\*)'), r'$1');
    out = out.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
    out = out.replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '');
    return out.trim();
  }

  /// Actually saves the action the assistant proposed. Only ever called
  /// from an explicit user tap on the confirmation card — the assistant
  /// itself never writes anything.
  Future<void> _confirmAction(_ChatMessage message) async {
    final action = message.action!;
    try {
      if (action.type == 'add_medicine') {
        final times = (action.data['times'] as List?)?.cast<String>() ?? [];
        if ((action.data['name'] as String? ?? '').isEmpty || times.isEmpty) {
          throw Exception('Missing name or times');
        }
        final frequencyStr = action.data['frequency'] as String? ?? 'daily';
        final customDays = (action.data['customDays'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            [];
        final endDateStr = action.data['endDate'] as String?;

        final medicine = Medicine(
          id: const Uuid().v4(),
          name: action.data['name'] as String,
          dosage: action.data['dosage'] as String? ?? '',
          instructions: action.data['instructions'] as String? ?? '',
          times: times,
          startDate: DateTime.now(),
          endDate: endDateStr != null ? DateTime.tryParse(endDateStr) : null,
          frequency: frequencyStr == 'custom'
              ? MedicineFrequency.custom
              : MedicineFrequency.daily,
          customDays: customDays,
        );
        await DatabaseService.instance.insertMedicine(medicine);
        try {
          await NotificationService.instance.scheduleMedicineReminders(medicine);
        } catch (_) {
          // Data is saved either way — see the same reasoning as the
          // Save button fix in medicine_list_screen.dart.
        }
      } else if (action.type == 'add_appointment') {
        final dateTimeStr = action.data['dateTime'] as String?;
        final dateTime = dateTimeStr != null ? DateTime.tryParse(dateTimeStr) : null;
        if ((action.data['doctorName'] as String? ?? '').isEmpty || dateTime == null) {
          throw Exception('Missing doctor name or date/time');
        }

        final appt = Appointment(
          id: const Uuid().v4(),
          doctorName: action.data['doctorName'] as String,
          location: action.data['location'] as String? ?? '',
          dateTime: dateTime,
        );
        await DatabaseService.instance.insertAppointment(appt);
        try {
          await NotificationService.instance.scheduleAppointmentReminder(appt);
        } catch (_) {}
      }

      setState(() {
        message.actionHandled = true;
        _messages.add(_ChatMessage(AppText.t('added_confirmation', _lang), false));
      });
    } catch (e) {
      final detail = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        message.actionHandled = true;
        _messages.add(_ChatMessage(
            "I couldn't save that ($detail). You can add it manually instead "
            "from My medicines or Appointments.",
            false));
      });
    }
  }

  void _dismissAction(_ChatMessage message) {
    setState(() => message.actionHandled = true);
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().languageCode;
    _lang = lang;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bubbleColor = isDark ? const Color(0xFF2A2D3A) : Colors.grey.shade200;
    final bubbleTextColor = isDark ? Colors.white : Colors.black87;
    final inputFillColor = isDark ? const Color(0xFF1E2028) : Colors.grey.shade100;

    return Scaffold(
      appBar: AppBar(title: Text(AppText.t('health_assistant', lang))),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(14),
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final m = _messages[i];
                final bubble = Align(
                  alignment:
                      m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75),
                    decoration: BoxDecoration(
                      color: m.fromUser ? const Color(0xFF5B7CFA) : bubbleColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      m.text,
                      style: TextStyle(
                          color: m.fromUser ? Colors.white : bubbleTextColor),
                    ),
                  ),
                );

                final showAction = m.action != null && !m.actionHandled;
                if (!showAction && m.docs == null) return bubble;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bubble,
                    if (showAction) _actionCard(context, m),
                    if (m.docs != null) _docsCard(context, m.docs!),
                  ],
                );
              },
            ),
          ),
          if (_sending)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(),
            ),
          if (_listening)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.mic, color: Colors.redAccent, size: 16),
                  const SizedBox(width: 6),
                  Text(AppText.t('listening', lang),
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                ],
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _speechAvailable ? _toggleListening : null,
                    icon: Icon(
                      _listening ? Icons.mic : Icons.mic_none,
                      color: _listening ? Colors.redAccent : null,
                    ),
                    tooltip: _speechAvailable
                        ? AppText.t('voice_input', lang)
                        : AppText.t('voice_input_unavailable', lang),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: AppText.t('chat_hint', lang),
                        filled: true,
                        fillColor: inputFillColor,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Results of a "find my report/prescription" request: one row per
  /// match with exactly two options — View and Download.
  Widget _docsCard(BuildContext context, List<_FoundDoc> docs) {
    final lang = context.read<SettingsService>().languageCode;
    final theme = Theme.of(context);

    if (docs.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(left: 4, bottom: 10, right: 60),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(AppText.t('no_docs_found', lang)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final d in docs)
          Container(
            margin: const EdgeInsets.only(left: 4, bottom: 10, right: 40),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.primary),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(d.isPrescription ? Icons.receipt_long : Icons.description,
                        color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(d.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(d.subtitle, style: theme.textTheme.bodySmall),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _viewDoc(d),
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: Text(AppText.t('doc_view', lang)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: d.hasFile
                            ? () => saveImageToGallery(context, d.filePath!, lang)
                            : null,
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: Text(AppText.t('doc_download', lang)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Confirmation card shown under an assistant message that proposes
  /// adding a medicine or appointment. Nothing is saved until "Confirm"
  /// is tapped — this is the same safety pattern used for AI-scanned
  /// prescriptions elsewhere in the app.
  Widget _actionCard(BuildContext context, _ChatMessage message) {
    final lang = context.read<SettingsService>().languageCode;
    final action = message.action!;
    final isMedicine = action.type == 'add_medicine';

    final title = isMedicine
        ? (action.data['name'] as String? ?? 'Medicine')
        : 'Dr. ${action.data['doctorName'] as String? ?? ''}';
    final subtitle = isMedicine
        ? '${action.data['dosage'] ?? ''} • ${((action.data['times'] as List?) ?? []).join(", ")}'
        : '${action.data['location'] ?? ''} • ${action.data['dateTime'] ?? ''}';

    return Container(
      margin: const EdgeInsets.only(left: 4, bottom: 10, right: 60),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.primary),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isMedicine ? Icons.medication : Icons.event,
                  color: Theme.of(context).colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isMedicine
                      ? AppText.t('add_medicine_q', lang)
                      : AppText.t('add_appointment_q', lang),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton(
                onPressed: () => _dismissAction(message),
                child: Text(AppText.t('not_now', lang)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _confirmAction(message),
                child: Text(AppText.t('confirm', lang)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
