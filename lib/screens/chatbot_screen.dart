import 'package:flutter/material.dart';
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
  late final List<_ChatMessage> _messages;
  bool _sending = false;

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
  Widget build(BuildContext context) {
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
                      color: m.fromUser ? const Color(0xFF5B7CFA) : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      m.text,
                      style: TextStyle(
                          color: m.fromUser ? Colors.white : Colors.black87),
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'e.g. "I missed my evening dose"',
                        filled: true,
                        fillColor: Colors.grey.shade100,
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
