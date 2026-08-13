// Updated Express backend using Google Gemini SDK Proxy
const express = require('express');
const cors = require('cors');
require('dotenv').config();

const { router: authRouter } = require('./auth');
const medicinesRouter = require('./medicines');
const appointmentsRouter = require('./appointments');
const prescriptionsRouter = require('./prescriptions');
const medicalReportsRouter = require('./medical_reports');
const healthRecordsRouter = require('./health_records');
const { router: appointmentCallsRouter, twilioWebhookRouter } = require('./appointment_calls');

// BUG FIX: this used to hardcode model: 'gemini-3.5-flash' at every call
// site below — that model name doesn't exist. Since an "unknown model"
// error isn't a 503 overload error, isOverloadedError() never caught it,
// so generateWithRetry() never fell back to FALLBACK_MODEL either — every
// single request (chat, prescription parsing, report summaries) failed
// immediately, every time. That's why the assistant only ever showed
// generic/fallback replies, never remembered anything, and could never
// successfully save a medicine or appointment through chat.
// The client + retry/fallback logic now lives in ai.js so the
// appointment-call feature (appointment_calls.js) can reuse it too.
const { generateWithRetry, isOverloadedError } = require('./ai');

const app = express();
app.use(cors());
// Twilio posts webhook data as application/x-www-form-urlencoded, not
// JSON — needed for the AI phone-call booking feature below.
app.use(express.urlencoded({ extended: false }));
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
// Authenticated endpoints the Flutter app calls (start a call, poll status).
app.use('/api/appointment-calls', appointmentCallsRouter);
// Unauthenticated webhooks Twilio itself calls back into during a live
// call — these can't carry your app's login token, so they're protected
// instead by the call's own unguessable UUID (see appointment_calls.js).
app.use('/api/appointment-calls', twilioWebhookRouter);

// ---------------------------------------------------------------------
// 1) Prescription text -> structured medicine suggestions
// ---------------------------------------------------------------------
app.post('/api/parse-prescription', async (req, res) => {
  try {
    const { rawText } = req.body;

    const response = await generateWithRetry({
      model: PRIMARY_MODEL,
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
    if (isOverloadedError(err)) {
      return res.status(503).json({
        error: 'ai_overloaded',
        message: 'The AI service is busy right now. Please try again in a moment.',
      });
    }
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
- If the message describes severe symptoms (difficulty breathing, chest
  pain, severe allergic reaction, confusion, fainting, suicidal thoughts,
  etc.), tell them clearly to seek emergency care immediately before
  anything else, and skip the steps below.
- Keep answers short, warm, and easy to read for someone who may be
  unwell or anxious.
- Never diagnose. Never name, suggest, or propose starting a new
  medicine, switching to an alternative, or changing a dose — not even
  a common over-the-counter one. This is true no matter how the patient
  phrases the request (e.g. "suggest a medicine", "what's a good
  alternative", "what should I take"). This restriction is absolute and
  does not soften even if the patient insists, says it's urgent, or
  says they can't reach a doctor right now — for those cases, point
  them to a pharmacist, nurse helpline, or urgent care instead of
  naming anything yourself.

When a patient describes a new or worsening symptom (not a question
about a medicine they're already told you about), follow this instead
of a generic deflection:
1. Ask 1-2 short, specific triage questions if you don't have enough to
   go on yet — e.g. how high a fever is, how long it's lasted, whether
   there are other symptoms — before saying anything else. Only do this
   once; if they've already answered, move on to the steps below rather
   than asking again.
2. Give general, non-drug-specific red-flag guidance for that symptom
   (e.g. when a fever or headache like this typically warrants urgent
   care vs. can be watched at home) — this is safe because it doesn't
   name any medicine.
3. Check ONLY the patient's CURRENT medicines list provided below — if
   one of them is commonly used for this exact symptom, or the symptom
   is a plausible side effect of one of them, you may mention that
   factually (e.g. "you're already taking X, which is sometimes used
   for headaches" or "this can sometimes be a side effect of Y you're
   on"). This is strictly informational about medicines they are
   ALREADY taking — never suggest a dose change, a new medicine, or an
   alternative, even here.
4. Always close by directing them to their doctor or pharmacist for
   what to actually take, and suggest they mention the symptom plus
   their current medicines when they do.
- Write your "reply" text the way a caring person would text a friend —
  plain conversational sentences only. Never use markdown formatting:
  no **bold**, no bullet points or numbered lists, no backticks or code
  blocks, no headings. If you want to list a few things, just say them
  in a sentence ("take it with breakfast and dinner") instead of a list.

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
    const { message, history, medicines, appointments, reports, profile, reportContext, language } = req.body;

    const contextParts = [];
    if (language === 'hi') {
      contextParts.push('Reply entirely in Hindi (हिन्दी), written in Devanagari '
        + 'script — not Hinglish or English. This applies to every "reply" you '
        + 'write, including clarifying questions and confirmations. Keep medicine '
        + 'names, dosage units, and dates as given (do not translate proper nouns '
        + 'or numbers), but every sentence around them should be natural Hindi.');
    }
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

    // BUG FIX: previously only `message` (the latest turn) was ever sent
    // to the model — every request was stateless, so the assistant had no
    // memory of anything said earlier in the same conversation and could
    // never handle a follow-up like "make it 9pm instead". Now we forward
    // the recent turns too, as proper multi-turn `contents`. Capped to the
    // last 20 turns so a long-running chat doesn't blow up token usage.
    const priorTurns = Array.isArray(history) ? history.slice(-20) : [];
    const contents = [
      ...priorTurns
        .filter(h => h && typeof h.text === 'string' && h.text.trim())
        .map(h => ({
          role: h.role === 'assistant' ? 'model' : 'user',
          parts: [{ text: h.text }],
        })),
      { role: 'user', parts: [{ text: message }] },
    ];

    const response = await generateWithRetry({
      model: PRIMARY_MODEL,
      contents,
      config: {
        systemInstruction: CHAT_SYSTEM_PROMPT + '\n\n' + contextParts.join('\n\n'),
        responseMimeType: 'application/json',
      }
    });

    const rawText = response.text;
    let parsed;
    try {
      const cleaned = rawText.replace(/```json|```/g, '').trim();
      parsed = JSON.parse(cleaned);
    } catch (parseErr) {
      // The model occasionally drifts from strict JSON despite
      // responseMimeType. Rather than fail the whole request, fall back
      // to showing the raw text as a plain reply with no action — a
      // degraded response beats a dead chatbot.
      console.error('Chat JSON parse failed, raw model output:', rawText);
      parsed = { reply: rawText, action: null };
    }

    res.json({ reply: parsed.reply ?? rawText, action: parsed.action ?? null });
  } catch (err) {
    console.error('Chat request failed:', err);
    if (isOverloadedError(err)) {
      return res.status(503).json({
        error: 'ai_overloaded',
        message: 'The AI service is busy right now. Please try again in a moment.',
      });
    }
    res.status(500).json({ error: 'chat_failed', message: err.message });
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

    const response = await generateWithRetry({
      model: PRIMARY_MODEL,
      contents: rawText,
      config: {
        systemInstruction: REPORT_SUMMARY_PROMPT,
      }
    });

    res.json({ summary: response.text });
  } catch (err) {
    console.error(err);
    if (isOverloadedError(err)) {
      return res.status(503).json({
        error: 'ai_overloaded',
        message: 'The AI service is busy right now. Please try again in a moment.',
      });
    }
    res.status(500).json({ error: 'summarize_failed' });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Backend running on port ${PORT}`));