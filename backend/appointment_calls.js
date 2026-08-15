// AI phone-call appointment booking.
//
// Flow: the app POSTs doctor phone + requested date/time (authenticated,
// see `router` below) -> we place a Twilio call -> Twilio hits our
// *unauthenticated* webhooks in `twilioWebhookRouter` as the call
// progresses -> each turn we feed the transcript-so-far to Gemini,
// speak its reply with Twilio's <Say>, and either keep listening
// (<Gather>) or hang up. The app polls GET /:id for status/transcript.
//
// SIMULATION MODE: calling a real, unverified phone number requires a
// paid (non-trial) Twilio account -- trial accounts can only call
// manually-verified numbers, and some Twilio trials now gate even
// *adding* a verified number behind an upgrade. So there's also a
// Twilio-free simulation path (POST /simulate, POST /:id/simulate-reply)
// that runs the exact same Gemini conversation logic below, driven by
// typed text instead of a real call -- useful for demos/development
// without needing a funded Twilio account. Simulated calls are flagged
// with is_simulated = true so the UI can label them clearly; they are
// never presented as if a real call happened.
//
// SETUP REQUIRED for REAL calls (see .env.example):
// - TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN / TWILIO_FROM_NUMBER from a
//   Twilio account. Twilio is NOT free for calling arbitrary numbers --
//   trial accounts can only call phone numbers you've manually verified
//   in the Twilio console, and prepend a "trial account" notice to every
//   call. To call a real doctor's office you need to upgrade to a
//   pay-as-you-go account (no minimum -- a few cents per minute).
// - PUBLIC_BASE_URL: a public HTTPS URL Twilio can reach for webhooks
//   (e.g. your deployed backend URL, or an ngrok URL in development).
//   Calls will fail to connect without this.
//
// PRIVACY: the call script deliberately never reads out the patient's
// medicines, reports, or health data to whoever answers the phone --
// only their name, the requested slot, and a callback number if asked.
// Scheduling a slot doesn't require sharing medical history.

const express = require('express');
const twilio = require('twilio');
const { requireAuth } = require('./auth');
const pool = require('./db');
const { generateWithRetry, isOverloadedError, PRIMARY_MODEL } = require('./ai');

const MAX_TURNS = 14; // hard cap so a stuck call can't loop forever / run up cost

function twilioClient() {
  const sid = process.env.TWILIO_ACCOUNT_SID;
  const token = process.env.TWILIO_AUTH_TOKEN;
  if (!sid || !token) return null;
  return twilio(sid, token);
}

function toJson(row) {
  return {
    id: row.id,
    doctorName: row.doctor_name,
    doctorPhone: row.doctor_phone,
    requestedDate: row.requested_date,
    requestedTime: row.requested_time,
    patientName: row.patient_name,
    notes: row.notes,
    status: row.status,
    outcome: row.outcome,
    outcomeSummary: row.outcome_summary,
    confirmedDateTime: row.confirmed_date_time,
    transcript: row.transcript || [],
    isSimulated: !!row.is_simulated,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function loadCall(id) {
  const result = await pool.query('SELECT * FROM appointment_calls WHERE id = $1', [id]);
  return result.rows[0] || null;
}

// ---------------------------------------------------------------------
// Shared conversation logic -- used by both the real Twilio webhooks and
// the Twilio-free simulation endpoints below, so the AI's behavior is
// identical either way.
// ---------------------------------------------------------------------

const CALL_SYSTEM_PROMPT = `You are an automated calling assistant placing
a phone call on behalf of a patient, to a doctor's office, to book or
confirm an appointment. A real person (receptionist, nurse, or the
doctor) will answer and speak with you.

Rules you always follow:
- Start by clearly identifying yourself as an automated assistant
  calling on behalf of the patient -- never pretend to be a human or
  the patient themselves. Something like: "Hello, this is an automated
  scheduling assistant calling on behalf of {patientName}, for an
  appointment with Dr. {doctorName}."
- Your goal is to book or confirm the requested date and time. If that
  slot isn't available, politely ask for the nearest available
  alternative and try to agree on one.
- Speak naturally, like a real spoken phone conversation -- short
  sentences, no lists, no markdown, no headers.
- NEVER share the patient's medicines, diagnoses, symptoms, or any
  other health/medical details. If asked why the appointment is needed,
  say the patient will share details in person, or that you don't have
  that information.
- If the person you're speaking with asks a question you can't answer
  (clinical questions, insurance details, anything outside scheduling),
  say the patient will call back directly -- don't guess.
- If you reach voicemail or an automated system instead of a person,
  leave a brief message with the request and a callback number if one
  was provided, then end the call.
- Keep the whole call efficient -- aim to reach a clear outcome (booked,
  declined, or "they'll call back") within a few exchanges, then end
  politely. Don't drag the conversation out once you have an answer.

You will be given the conversation so far (if any) and must respond
with ONLY a JSON object, no other text, in this exact shape:
{
  "say": "<what to say next, spoken naturally, 1-3 sentences>",
  "done": <true if the call should end after this line, false to keep listening for a reply>,
  "outcome": "<one of: confirmed | declined | needs_followup | unclear | null>",
  "confirmedDateTime": "<ISO 8601 datetime if a specific slot was confirmed, else null>",
  "summary": "<one short sentence summarizing the outcome for the patient, or null if not done yet>"
}
Only set "outcome"/"confirmedDateTime"/"summary" when "done" is true.`;

function buildContextPreamble(call) {
  return [
    `Patient name: ${call.patient_name || 'the patient'}.`,
    `Doctor name: ${call.doctor_name || 'the doctor'}.`,
    `Requested date: ${call.requested_date}. Requested time: ${call.requested_time}.`,
    call.notes ? `Extra scheduling notes (not medical): ${call.notes}` : null,
  ].filter(Boolean).join('\n');
}

async function nextTurn(call, transcript) {
  const history = transcript
    .map(t => `${t.role === 'assistant' ? 'You' : 'Them'}: ${t.text}`)
    .join('\n');

  try {
    const response = await generateWithRetry({
      model: PRIMARY_MODEL,
      contents: [{
        role: 'user',
        parts: [{
          text: `${buildContextPreamble(call)}\n\nConversation so far:\n${history || '(call just connected, nothing said yet)'}\n\nRespond with the JSON object now.`,
        }],
      }],
      config: {
        systemInstruction: CALL_SYSTEM_PROMPT,
        responseMimeType: 'application/json',
      },
    });
    const text = response.text ?? response.candidates?.[0]?.content?.parts?.[0]?.text ?? '{}';
    return JSON.parse(text);
  } catch (err) {
    console.error('Gemini call-turn generation failed:', err);
    return {
      say: "I'm sorry, I'm having trouble right now. I'll have the patient call you back directly. Thank you, goodbye.",
      done: true,
      outcome: 'needs_followup',
      confirmedDateTime: null,
      summary: 'The assistant hit a technical error mid-call; the patient should call the office directly.',
    };
  }
}

// Appends the incoming line (if any) to the transcript, asks Gemini (or
// synthesizes a wrap-up if MAX_TURNS is hit) for the next assistant line,
// persists the updated call row, and returns { turn, transcript,
// turnCount } for the caller (TwiML builder or JSON responder) to use.
async function advanceCall(call, incomingText) {
  const transcript = call.transcript || [];
  if (incomingText) transcript.push({ role: 'them', text: incomingText });

  const turnCount = call.turn_count + (incomingText ? 1 : 0);
  const forceWrapUp = turnCount >= MAX_TURNS;

  const turn = forceWrapUp
    ? {
        say: "I want to be respectful of your time, so I'll have the patient follow up directly from here. Thank you very much, goodbye.",
        done: true,
        outcome: 'needs_followup',
        confirmedDateTime: null,
        summary: 'The call ran long without a clear resolution; the patient should follow up directly.',
      }
    : await nextTurn(call, transcript);

  transcript.push({ role: 'assistant', text: turn.say });

  if (turn.done) {
    await pool.query(
      `UPDATE appointment_calls SET
         status = 'completed', outcome = $1, outcome_summary = $2,
         confirmed_date_time = $3, transcript = $4, turn_count = $5, updated_at = now()
       WHERE id = $6`,
      [turn.outcome || 'unclear', turn.summary || null, turn.confirmedDateTime || null,
       JSON.stringify(transcript), turnCount, call.id]
    );
  } else {
    await pool.query(
      `UPDATE appointment_calls SET
         status = 'in_progress', transcript = $1, turn_count = $2, updated_at = now()
       WHERE id = $3`,
      [JSON.stringify(transcript), turnCount, call.id]
    );
  }

  return { turn, transcript, turnCount };
}

// ---------------------------------------------------------------------
// Authenticated routes the Flutter app calls directly.
// ---------------------------------------------------------------------
const router = express.Router();
router.use(requireAuth);

router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM appointment_calls WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50',
      [req.userId]
    );
    res.json({ calls: result.rows.map(toJson) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'fetch_failed', message: err.message });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM appointment_calls WHERE id = $1 AND user_id = $2',
      [req.params.id, req.userId]
    );
    if (!result.rows[0]) return res.status(404).json({ error: 'not_found' });
    res.json({ call: toJson(result.rows[0]) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'fetch_failed', message: err.message });
  }
});

router.post('/', async (req, res) => {
  try {
    const { doctorName, doctorPhone, requestedDate, requestedTime, patientName, notes } = req.body;
    if (!doctorPhone || !requestedDate || !requestedTime) {
      return res.status(400).json({ error: 'missing_fields' });
    }

    const base = process.env.PUBLIC_BASE_URL;
    const client = twilioClient();
    if (!client || !process.env.TWILIO_FROM_NUMBER || !base) {
      return res.status(503).json({
        error: 'calling_not_configured',
        message:
          'AI phone booking isn\'t set up yet. Add TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, ' +
          'TWILIO_FROM_NUMBER, and PUBLIC_BASE_URL to the backend .env file (see .env.example).',
      });
    }

    const insertResult = await pool.query(
      `INSERT INTO appointment_calls
         (user_id, doctor_name, doctor_phone, requested_date, requested_time, patient_name, notes, status)
       VALUES ($1,$2,$3,$4,$5,$6,$7,'queued')
       RETURNING *`,
      [req.userId, doctorName || null, doctorPhone, requestedDate, requestedTime, patientName || null, notes || '']
    );
    const call = insertResult.rows[0];

    try {
      const twilioCall = await client.calls.create({
        to: doctorPhone,
        from: process.env.TWILIO_FROM_NUMBER,
        url: `${base}/api/appointment-calls/${call.id}/voice`,
        statusCallback: `${base}/api/appointment-calls/${call.id}/status`,
        // statusCallbackEvent only accepts these 4 trigger-point values
        // (initiated/ringing/answered/completed) -- NOT call outcomes like
        // busy/no-answer/failed/canceled. 'completed' fires once the call
        // reaches any final state, and the actual outcome shows up in
        // CallStatus on that same webhook (see /:id/status below).
        statusCallbackEvent: ['initiated', 'ringing', 'answered', 'completed'],
        statusCallbackMethod: 'POST',
      });
      await pool.query(
        `UPDATE appointment_calls SET status = 'ringing', twilio_call_sid = $1, updated_at = now() WHERE id = $2`,
        [twilioCall.sid, call.id]
      );
    } catch (twilioErr) {
      console.error('Twilio call.create failed:', twilioErr);
      await pool.query(
        `UPDATE appointment_calls SET status = 'failed', outcome_summary = $1, updated_at = now() WHERE id = $2`,
        [`Could not place the call: ${twilioErr.message || 'unknown Twilio error'}`, call.id]
      );
      return res.status(502).json({ error: 'call_failed', message: twilioErr.message });
    }

    res.json({ call: toJson({ ...call, status: 'ringing' }) });
  } catch (err) {
    console.error(err);
    // Common cause: schema.sql wasn't re-run after this feature was added,
    // so the appointment_calls table doesn't exist yet (Postgres error
    // code 42P01 = undefined_table). Surface that plainly instead of a
    // bare "create_failed" the app can't do anything useful with.
    if (err.code === '42P01') {
      return res.status(500).json({
        error: 'missing_table',
        message:
          'The appointment_calls table doesn\'t exist yet. Re-run schema.sql ' +
          'against your database (see README -> "Setting up the AI phone-call ' +
          'booking feature").',
      });
    }
    res.status(500).json({ error: 'create_failed', message: err.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM appointment_calls WHERE id = $1 AND user_id = $2',
      [req.params.id, req.userId]
    );
    const call = result.rows[0];
    if (!call) return res.status(404).json({ error: 'not_found' });

    if (call.twilio_call_sid && ['queued', 'ringing', 'in_progress'].includes(call.status)) {
      const client = twilioClient();
      if (client) {
        try {
          await client.calls(call.twilio_call_sid).update({ status: 'completed' });
        } catch (e) {
          console.warn('Could not hang up in-progress call:', e.message);
        }
      }
    }
    await pool.query(
      `UPDATE appointment_calls SET status = 'canceled', updated_at = now() WHERE id = $1`,
      [call.id]
    );
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'cancel_failed', message: err.message });
  }
});

// --- Simulation mode: no Twilio, no real phone call -------------------
// Same Gemini conversation logic as a real call, driven by typed text.
// Useful for demos/dev when Twilio isn't set up or is trial-restricted.

router.post('/simulate', async (req, res) => {
  try {
    const { doctorName, requestedDate, requestedTime, patientName, notes } = req.body;
    if (!requestedDate || !requestedTime) {
      return res.status(400).json({ error: 'missing_fields' });
    }

    const insertResult = await pool.query(
      `INSERT INTO appointment_calls
         (user_id, doctor_name, doctor_phone, requested_date, requested_time, patient_name, notes, status, is_simulated)
       VALUES ($1,$2,'(simulated -- no real call placed)',$3,$4,$5,$6,'in_progress',true)
       RETURNING *`,
      [req.userId, doctorName || null, requestedDate, requestedTime, patientName || null, notes || '']
    );
    const call = insertResult.rows[0];
    call.transcript = [];

    await advanceCall(call, null);
    const updated = await loadCall(call.id);
    res.json({ call: toJson(updated) });
  } catch (err) {
    console.error(err);
    if (err.code === '42P01' || err.code === '42703') {
      return res.status(500).json({
        error: 'missing_table_or_column',
        message:
          'The appointment_calls table (or its is_simulated column) is missing. ' +
          'Re-run schema.sql against your database.',
      });
    }
    res.status(500).json({ error: 'simulate_start_failed', message: err.message });
  }
});

router.post('/:id/simulate-reply', async (req, res) => {
  try {
    const { text } = req.body;
    if (!text || !text.trim()) {
      return res.status(400).json({ error: 'missing_text' });
    }

    const result = await pool.query(
      'SELECT * FROM appointment_calls WHERE id = $1 AND user_id = $2',
      [req.params.id, req.userId]
    );
    const call = result.rows[0];
    if (!call) return res.status(404).json({ error: 'not_found' });
    if (!call.is_simulated) {
      return res.status(400).json({ error: 'not_simulated', message: 'This call is not a simulation.' });
    }
    if (['completed', 'canceled'].includes(call.status)) {
      return res.status(400).json({ error: 'already_finished', message: 'This simulated call has already ended.' });
    }

    await advanceCall(call, text.trim());
    const updated = await loadCall(call.id);
    res.json({ call: toJson(updated) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'simulate_reply_failed', message: err.message });
  }
});

// ---------------------------------------------------------------------
// Unauthenticated webhooks -- Twilio itself calls these while a REAL
// phone call is live. Protected only by the call's own unguessable UUID
// (Twilio can't send our app's login token), same trust model as e.g.
// Stripe webhook URLs with a secret path component.
// ---------------------------------------------------------------------
const twilioWebhookRouter = express.Router();
const { VoiceResponse } = twilio.twiml;

function speak(twiml, text) {
  twiml.say({ voice: 'Polly.Joanna' }, text);
}

async function respondForTurn(req, res, id) {
  const call = await loadCall(id);
  const twiml = new VoiceResponse();
  if (!call) {
    speak(twiml, 'Sorry, something went wrong on our end. Goodbye.');
    twiml.hangup();
    res.type('text/xml').send(twiml.toString());
    return;
  }

  const { turn } = await advanceCall(call, req.body.SpeechResult || null);
  speak(twiml, turn.say);

  if (turn.done) {
    twiml.hangup();
  } else {
    twiml.gather({
      input: 'speech',
      action: `/api/appointment-calls/${id}/gather`,
      method: 'POST',
      speechTimeout: 'auto',
      timeout: 6,
    });
    // If gather times out with no input at all, Twilio falls through here.
    speak(twiml, "Sorry, I didn't catch that. I'll have the patient follow up directly. Goodbye.");
    twiml.hangup();
  }

  res.type('text/xml').send(twiml.toString());
}

// Initial webhook when the call connects.
twilioWebhookRouter.post('/:id/voice', async (req, res) => {
  await respondForTurn(req, res, req.params.id);
});

// Follow-up webhook after each <Gather>.
twilioWebhookRouter.post('/:id/gather', async (req, res) => {
  await respondForTurn(req, res, req.params.id);
});

// Call-level status updates (no-answer, busy, failed, canceled, completed
// via hangup rather than our own <Hangup>).
twilioWebhookRouter.post('/:id/status', async (req, res) => {
  try {
    const call = await loadCall(req.params.id);
    if (call && !['completed', 'canceled'].includes(call.status)) {
      const statusMap = {
        'no-answer': 'no_answer',
        busy: 'busy',
        failed: 'failed',
        canceled: 'canceled',
        completed: 'completed',
      };
      const mapped = statusMap[req.body.CallStatus] || call.status;
      await pool.query(
        `UPDATE appointment_calls SET status = $1, updated_at = now() WHERE id = $2 AND status NOT IN ('completed','canceled')`,
        [mapped, call.id]
      );
    }
  } catch (err) {
    console.error('status webhook error:', err);
  }
  res.sendStatus(200);
});

module.exports = { router, twilioWebhookRouter };
