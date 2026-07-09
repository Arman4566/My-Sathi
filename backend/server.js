// Updated Express backend using Google Gemini SDK Proxy
const express = require('express');
const cors = require('cors');
const { GoogleGenAI } = require('@google/genai');
require('dotenv').config();

const { router: authRouter } = require('./auth');
const medicinesRouter = require('./medicines');
const appointmentsRouter = require('./appointments');
const prescriptionsRouter = require('./prescriptions');
const medicalReportsRouter = require('./medical_reports');
const healthRecordsRouter = require('./health_records');

const app = express();
app.use(cors());
app.use(express.json());

// User accounts (signup/login/forgot-password) and per-user data —
// everything below follows the same pattern, see medicines.js for the
// annotated version.
app.use('/api/auth', authRouter);
app.use('/api/medicines', medicinesRouter);
app.use('/api/appointments', appointmentsRouter);
app.use('/api/prescriptions', prescriptionsRouter);
app.use('/api/medical-reports', medicalReportsRouter);
app.use('/api/health-records', healthRecordsRouter);

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
// 2) Patient chatbot — safety-first system prompt, full app context, and
//    the ability to PROPOSE adding a medicine or appointment.
//
//    IMPORTANT: the model never writes data directly — it only returns a
//    structured "action" alongside its reply. The Flutter app always
//    shows this to the user as a confirmation card before actually
//    saving anything (see chatbot_screen.dart). This mirrors the same
//    "AI suggests, human confirms" pattern already used for prescription
//    scanning — never trust AI-parsed medical data blindly.
// ---------------------------------------------------------------------
const CHAT_SYSTEM_PROMPT = `You are a supportive assistant inside a
medicine-reminder app called Sathi. You are NOT a doctor and must never
act like one.

Safety rules you always follow:
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
  etc.), tell them clearly to seek emergency care immediately before
  anything else.
- Keep answers short, warm, and easy to read for someone who may be
  unwell or anxious.
- Never diagnose, never recommend starting/stopping/changing a dose.

You are given the patient's current medicines, appointments, recent
report summaries, and basic profile below. Use this to answer questions
about their own situation accurately (e.g. "what am I currently taking",
"when is my next appointment", "what did my last report say") — but
never invent details that aren't in the provided data.

You can also help the patient ADD a medicine or appointment through
conversation. If they clearly ask to add/schedule one AND give enough
information to do so safely and specifically (medicine: name, dose, at
least one time; appointment: doctor name, date, time), include an
"action" object in your response (schema below). If information is
missing or ambiguous, do NOT guess — ask a clarifying question in your
reply instead, and leave action null. Never propose an action the
patient didn't ask for.

Respond with ONLY valid JSON (no prose, no markdown fences) in exactly
this shape:
{
  "reply": "your conversational reply as plain text",
  "action": null
}
or, when proposing an action:
{
  "reply": "your conversational reply, e.g. confirming what you're about to add",
  "action": {
    "type": "add_medicine",
    "name": "", "dosage": "", "instructions": "",
    "times": ["HH:MM"], "frequency": "daily",
    "customDays": [], "endDate": null
  }
}
or:
{
  "reply": "...",
  "action": {
    "type": "add_appointment",
    "doctorName": "", "location": "", "dateTime": "YYYY-MM-DDTHH:MM:00"
  }
}`;

app.post('/api/chat', async (req, res) => {
  try {
    const { message, medicines, appointments, reports, profile, reportContext } = req.body;

    const contextParts = [];
    if (medicines?.length) {
      contextParts.push(`Current medicines:\n${medicines
        .map(m => `- ${m.name} (${m.dosage}), ${m.instructions}, times: ${(m.times || []).join(', ')}, frequency: ${m.frequency}${m.endDate ? `, until ${m.endDate}` : ''}`)
        .join('\n')}`);
    }
    if (appointments?.length) {
      contextParts.push(`Upcoming appointments:\n${appointments
        .map(a => `- Dr. ${a.doctorName} at ${a.location}, ${a.dateTime}`)
        .join('\n')}`);
    }
    if (reports?.length) {
      contextParts.push(`Recent report summaries:\n${reports
        .map(r => `- ${r.title} (${r.uploadedDate}): ${r.summary}`)
        .join('\n')}`);
    }
    if (profile) {
      contextParts.push(`Patient profile: age ${profile.age ?? 'unknown'}, weight ${profile.weightKg ?? 'unknown'}kg, height ${profile.heightCm ?? 'unknown'}cm, gender ${profile.gender ?? 'unknown'}.`);
    }
    if (reportContext) {
      contextParts.push(`The patient opened this chat from a specific scanned report. Its text:\n"""${reportContext}"""`);
    }
    // Today's date, since the model has no other way to know it — needed
    // for it to propose sensible dateTime/endDate values.
    contextParts.push(`Today's date is ${new Date().toISOString().slice(0, 10)}.`);

    const response = await ai.models.generateContent({
      model: 'gemini-3.5-flash',
      contents: message,
      config: {
        systemInstruction: CHAT_SYSTEM_PROMPT + '\n\n' + contextParts.join('\n\n'),
        responseMimeType: 'application/json',
      }
    });

    const parsed = JSON.parse(response.text);
    res.json({ reply: parsed.reply, action: parsed.action ?? null });
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