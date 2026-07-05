// Updated Express backend using Google Gemini SDK Proxy
const express = require('express');
const cors = require('cors');
const { GoogleGenAI } = require('@google/genai');
require('dotenv').config();

const { router: authRouter } = require('./auth');
const medicinesRouter = require('./medicines');

const app = express();
app.use(cors());
app.use(express.json());

// User accounts (signup/login/forgot-password) and per-user data.
// See auth.js and medicines.js — medicines.js is the worked example to
// copy for appointments/prescriptions/medical_reports/health_records.
app.use('/api/auth', authRouter);
app.use('/api/medicines', medicinesRouter);

// Automatically initializes using process.env.GEMINI_API_KEY
const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

// ---------------------------------------------------------------------
// 1) Prescription text -> structured medicine suggestions
// ---------------------------------------------------------------------
app.post('/api/parse-prescription', async (req, res) => {
  try {
    const { rawText } = req.body;

    const response = await ai.models.generateContent({
      model: 'gemini-3.5-flash',
      contents: `You extract medicine details from raw OCR text of a doctor's
prescription. The OCR text may be messy, misspelled, or incomplete because
handwriting recognition is imperfect. Return ONLY valid JSON, no prose, no
markdown fences, in this exact shape:
{"medicines":[{"name":"","dosage":"","instructions":"","suggestedTimes":["HH:MM"]}]}
If you are not confident about a field, leave it as an empty string or empty
array rather than guessing. Never invent a medicine that is not clearly
referenced in the text. Here is the raw text to parse: \n\n${rawText}`,
      config: {
        responseMimeType: 'application/json',
      }
    });

    const text = response.text;
    const parsed = JSON.parse(text);
    res.json(parsed);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'parse_failed' });
  }
});

// ---------------------------------------------------------------------
// 2) Patient chatbot — safety-first system prompt.
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

    const response = await ai.models.generateContent({
      model: 'gemini-3.5-flash',
      contents: message,
      config: {
        systemInstruction: CHAT_SYSTEM_PROMPT + '\n' + medsContext + reportBlock,
      }
    });

    res.json({ reply: response.text });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'chat_failed' });
  }
});

// ---------------------------------------------------------------------
// 3) Medical report summary — patient uploads a lab report / doctor's
//    note, we OCR it on-device (Flutter side) and send the raw text here
//    for a plain-language summary they can read anytime.
// ---------------------------------------------------------------------
const REPORT_SUMMARY_PROMPT = `You summarize a medical report or lab result
for a patient (not a doctor) to read. Rules:
- Use plain, everyday language, no unexplained jargon.
- Structure your reply as: a 2-3 sentence overview, then a short bullet
  list of the key values/findings and whether each is in the normal range
  if that's stated or clearly inferable from the text.
- If a value looks abnormal, say so plainly but do NOT diagnose a
  condition or tell them what to do about it — just note it and suggest
  they discuss it with their doctor.
- If the text is too garbled/incomplete to summarize confidently, say so
  honestly rather than guessing.
- Keep the whole summary under 200 words.`;

app.post('/api/summarize-report', async (req, res) => {
  try {
    const { rawText } = req.body;
    if (!rawText || !rawText.trim()) {
      return res.status(400).json({ error: 'no_text' });
    }

    const response = await ai.models.generateContent({
      model: 'gemini-3.5-flash',
      contents: rawText,
      config: {
        systemInstruction: REPORT_SUMMARY_PROMPT,
      }
    });

    res.json({ summary: response.text });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'summarize_failed' });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Backend running on port ${PORT}`));