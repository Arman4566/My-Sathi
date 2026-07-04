// Updated Express backend using Google Gemini SDK Proxy
const express = require('express');
const cors = require('cors');
const { GoogleGenAI } = require('@google/genai');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

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

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Backend running on port ${PORT}`));