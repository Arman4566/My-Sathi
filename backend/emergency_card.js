// Emergency Medical Card — see emergency_card_pdf.js for the full
// reasoning behind why only ONE field on this PDF (the closing "Quick
// Summary" line) is AI-generated, and everything else (blood group,
// allergies, chronic conditions, medicines) is the patient's own data
// passed straight through unmodified.
//
// Unauthenticated by design, same as /api/summarize-report and
// /api/check-interactions: the client already has this data locally
// (it's the patient's own profile + medicines) and sends it directly in
// the request body rather than this route querying the database itself.
// This keeps it consistent with the rest of the AI-proxy endpoints and
// means it still works even if the patient is offline from the main
// account sync but has the data cached locally.
const express = require('express');
const { generateWithRetry, isOverloadedError, isQuotaExceededError, PRIMARY_MODEL } = require('./ai');
const { buildEmergencyCardPdf } = require('./emergency_card_pdf');

const router = express.Router();

const EMERGENCY_CARD_PROMPT = `You write a single short plain-language
summary paragraph for a patient's Emergency Medical Card, meant to be
read in seconds by a family member or an ER doctor who doesn't know the
patient.

You will be given the patient's blood group, allergies, chronic
conditions, and current medicines. Your job is ONLY to restate this
information as 2-3 short, clear sentences a stressed reader can scan
instantly — NOT to add any new medical information, NOT to infer
anything not explicitly given, and NOT to give advice or a diagnosis.

Rules:
- If allergies are listed, mention them first — this is the single most
  safety-critical fact on the card.
- Mention chronic conditions and the number/type of medicines briefly.
- If a field is empty or "None recorded", it is fine to omit it or say
  so briefly — never invent a value to fill a gap.
- Never suggest a treatment, dosage change, or medical action.
- Plain text only, no markdown, under 60 words.
- Return ONLY valid JSON, no prose, no markdown fences, in this exact
  shape: {"summary":""}`;

router.post('/', async (req, res) => {
  try {
    const {
      patientName, age, gender, bloodGroup, allergies, chronicConditions,
      medicines,
    } = req.body;

    const medicineList = Array.isArray(medicines) ? medicines : [];
    // Trimmed, display-ready rows for the PDF table (raw times array ->
    // one readable string) — kept separate from what's sent to the model
    // below, which only needs names/dosages to write its summary.
    const medicineRows = medicineList.map((m) => ({
      name: m?.name || '',
      dosage: m?.dosage || '',
      times: Array.isArray(m?.times) ? m.times.join(', ') : (m?.times || ''),
    }));

    let summary = '';
    try {
      const response = await generateWithRetry({
        model: PRIMARY_MODEL,
        contents: JSON.stringify({
          bloodGroup: bloodGroup || null,
          allergies: allergies || null,
          chronicConditions: chronicConditions || null,
          medicines: medicineRows.map((m) => `${m.name} ${m.dosage}`.trim()),
        }),
        config: {
          systemInstruction: EMERGENCY_CARD_PROMPT,
          responseMimeType: 'application/json',
        },
      });
      const parsed = JSON.parse(response.text);
      summary = parsed.summary || '';
    } catch (aiErr) {
      // Non-fatal — the card is still fully usable without the AI
      // recap; every field that actually matters in an emergency
      // (allergies, meds, blood group) is already on the PDF verbatim.
      console.error('Emergency card AI summary failed, continuing without it:', aiErr);
    }

    const pdfBuffer = await buildEmergencyCardPdf({
      patientName: patientName || 'Not provided',
      age: age ?? null,
      gender: gender || null,
      bloodGroup: bloodGroup || null,
      allergies: allergies || null,
      chronicConditions: chronicConditions || null,
      medicines: medicineRows,
      aiSummary: summary,
      generatedAt: new Date(),
    });

    res.json({
      summary,
      pdfBase64: pdfBuffer.toString('base64'),
    });
  } catch (err) {
    console.error('Emergency card generation failed:', err);
    if (isOverloadedError(err)) {
      return res.status(503).json({
        error: 'ai_overloaded',
        message: 'The AI service is busy right now. Please try again in a moment.',
      });
    }
    if (isQuotaExceededError(err)) {
      return res.status(429).json({
        error: 'ai_quota_exceeded',
        message: 'The AI service has hit its usage limit for now. Please try again later.',
      });
    }
    res.status(500).json({ error: 'emergency_card_failed', message: err.message });
  }
});

module.exports = router;
