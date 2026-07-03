// Minimal Express backend that proxies requests from the Flutter app
// to Claude's API. Deploy this somewhere (Render/Railway/Fly.io/your own
// server) and put its URL into ai_backend_service.dart.
//
// Run: npm init -y && npm install express cors @anthropic-ai/sdk dotenv
//      node server.js

const express = require('express');
const cors = require('cors');
const Anthropic = require('@anthropic-ai/sdk');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

// ---------------------------------------------------------------------
// 1) Prescription text -> structured medicine suggestions
// ---------------------------------------------------------------------
app.post('/api/parse-prescription', async (req, res) => {
  try {
    const { rawText } = req.body;

    const response = await anthropic.messages.create({
      model: 'claude-sonnet-4-6',
      max_tokens: 1000,
      system: `You extract medicine details from raw OCR text of a doctor's
prescription. The OCR text may be messy, misspelled, or incomplete because
handwriting recognition is imperfect. Return ONLY valid JSON, no prose, no
markdown fences, in this exact shape:
{"medicines":[{"name":"","dosage":"","instructions":"","suggestedTimes":["HH:MM"]}]}
If you are not confident about a field, leave it as an empty string or empty
array rather than guessing. Never invent a medicine that is not clearly
referenced in the text.`,
      messages: [{ role: 'user', content: rawText }],
    });

    const text = response.content.map(b => b.text || '').join('');
    const cleaned = text.replace(/```json|```/g, '').trim();
    const parsed = JSON.parse(cleaned);
    res.json(parsed);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'parse_failed' });
  }
});

// ---------------------------------------------------------------------
// 2) Patient chatbot — safety-first system prompt.
//    This is the core guardrail: the model is explicitly told NOT to
//    give specific dosing/timing instructions, and to always route
//    anything specific back to a doctor or pharmacist. It's a support
//    layer, not a clinical decision-maker.
// ---------------------------------------------------------------------
const CHAT_SYSTEM_PROMPT = `You are a supportive assistant inside a
medicine-reminder app. You are NOT a doctor and must never act like one.

Rules you always follow:
- For questions like "I missed a dose, what do I do?": give general,
  widely-applicable safety information only (e.g. "many medicines can be
  taken as soon as you remember unless it's almost time for the next dose,
  but this varies a lot by medicine — check the leaflet or call your
  pharmacist to be sure"). Do NOT give a specific instruction for their
  specific medicine, since getting this wrong can be dangerous.
- Always encourage contacting their doctor, pharmacist, or a nurse helpline
  for anything specific to their medicine, dose, or condition.
- If the message describes severe symptoms (difficulty breathing, chest
  pain, severe allergic reaction, confusion, fainting, suicidal thoughts,
  etc.), tell them clearly to seek emergency care immediately (e.g. call
  their local emergency number) before anything else.
- Keep answers short, warm, and easy to read for someone who may be
  unwell or anxious.
- Never diagnose, never recommend starting/stopping/changing a dose.`;

app.post('/api/chat', async (req, res) => {
  try {
    const { message, currentMedicines, reportContext } = req.body;
    const medsContext = currentMedicines?.length
      ? `The patient is currently taking: ${currentMedicines.join(', ')}.`
      : '';
    const reportBlock = reportContext
      ? `\nThe patient opened this chat from a specific scanned report. Its text:\n"""${reportContext}"""\nYou may refer to it if relevant to their question.`
      : '';

    const response = await anthropic.messages.create({
      model: 'claude-sonnet-4-6',
      max_tokens: 500,
      system: CHAT_SYSTEM_PROMPT + '\n' + medsContext + reportBlock,
      messages: [{ role: 'user', content: message }],
    });

    const reply = response.content.map(b => b.text || '').join('');
    res.json({ reply });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'chat_failed' });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Backend running on port ${PORT}`));
