import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/ai_backend_service.dart';
import '../services/database_service.dart';

class _ChatMessage {
  final String text;
  final bool fromUser;
  _ChatMessage(this.text, this.fromUser);
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

  @override
  void initState() {
    super.initState();
    _messages = [
      _ChatMessage(
        widget.initialContextLabel != null
            ? "Hi! I can see you'd like to discuss: ${widget.initialContextLabel}. "
                "Ask me anything about it — I'll explain in plain language. "
                "For anything specific to your treatment, I'll always suggest "
                "checking with your doctor or pharmacist too."
            : "Hi! I'm your health assistant. I can help with general questions "
                "about your reminders, or point you in the right direction if you're "
                "not sure what to do. For anything specific to your medicine or "
                "condition, I'll always suggest checking with your doctor or "
                "pharmacist — that's for your safety.",
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

    setState(() {
      _messages.add(_ChatMessage(text, true));
      _sending = true;
      _controller.clear();
    });

    try {
      final meds = await DatabaseService.instance.getActiveMedicines();
      final names = meds.map((m) => m.name).toList();
      final reply = await AiBackendService.instance.sendChatMessage(
        message: text,
        currentMedicineNames: names,
        reportContext: widget.initialContextText,
      );
      setState(() => _messages.add(_ChatMessage(reply, false)));
    } catch (e) {
      setState(() => _messages.add(_ChatMessage(
          "Sorry, I couldn't reach the assistant right now. If this is "
          "urgent, please contact your doctor or pharmacist directly.",
          false)));
    } finally {
      setState(() => _sending = false);
      await Future.delayed(const Duration(milliseconds: 100));
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bubbleColor = isDark ? const Color(0xFF2A2D3A) : Colors.grey.shade200;
    final bubbleTextColor = isDark ? Colors.white : Colors.black87;
    final inputFillColor = isDark ? const Color(0xFF1E2028) : Colors.grey.shade100;

    return Scaffold(
      appBar: AppBar(title: const Text('Health Assistant')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(14),
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final m = _messages[i];
                return Align(
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
                  Icon(Icons.mic, color: Colors.redAccent, size: 16),
                  const SizedBox(width: 6),
                  Text('Listening…',
                      style: TextStyle(color: Colors.redAccent, fontSize: 12)),
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
                        ? 'Voice input'
                        : 'Voice input unavailable on this device',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'e.g. "I missed my evening dose"',
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
}
