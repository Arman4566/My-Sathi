// Minimal Express backend that proxies requests from the Flutter app
// to Gemini's API. Deploy this somewhere (Render/Railway/Fly.io/your own
// server) and put its URL into ai_backend_service.dart.
//
// Run: npm init -y && npm install express cors @google/genai dotenv
//      node server.js

const express = require('express');
const cors = require('cors');
const { GoogleGenAI } = require('@google/genai');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

// Initialize Google Gen AI with your API key from environment variables
// (Do not hardcode your key here! Keep it securely in Render/your .env file)
const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

// ---------------------------------------------------------------------
// 1) Prescription text -> structured medicine suggestions
// ---------------------------------------------------------------------
app.post('/api/parse-prescription', async (req, res) => {
  try {
    const { rawText } = req.body;

    const response = await ai.models.generateContent({
      model: 'gemini-1.5-flash',
      contents: `You extract medicine details from raw OCR text of a doctor's
prescription. The OCR text may be messy, misspelled, or incomplete because
handwriting recognition is imperfect. Return ONLY valid JSON matching the exact schema structure required.
Never invent a medicine that is not clearly referenced in the text. Here is the raw text to parse: \n\n${rawText}`,
      config: {
        // Enforces the model to return valid, un-fenced JSON
        responseMimeType: 'application/json',
        systemInstruction: `If you are not confident about a field, leave it as an empty string or empty array rather than guessing.`,
        // Defining the exact JSON structure so Gemini follows it perfectly
        responseSchema: {
          type: 'OBJECT',
          properties: {
            medicines: {
              type: 'ARRAY',
              items: {
                type: 'OBJECT',
                properties: {
                  name: { type: 'STRING' },
                  dosage: { type: 'STRING' },
                  instructions: { type: 'STRING' },
                  suggestedTimes: {
                    type: 'ARRAY',
                    items: { type: 'STRING' }
                  }
                },
                required: ['name', 'dosage', 'instructions', 'suggestedTimes']
              }
            }
          },
          required: ['medicines']
        }
      }
    });

    // Gemini returns clean text directly when responseMimeType is set to application/json
    const parsed = JSON.parse(response.text);
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
      model: 'gemini-2.0-flash',
      contents: message,
      config: {
        systemInstruction: CHAT_SYSTEM_PROMPT + '\n' + medsContext + reportBlock,
        maxOutputTokens: 500,
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