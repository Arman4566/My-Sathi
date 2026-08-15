// Shared Gemini client + retry/fallback helper. Originally lived inline
// in server.js; pulled out here so appointment_calls.js (AI phone-call
// booking) can reuse the exact same retry/fallback behavior instead of
// duplicating it — see server.js's comment history for why the retry
// logic exists (503 overload handling) and why the model name matters
// (a bad hardcoded model name previously broke every AI feature at once).
const { GoogleGenAI } = require('@google/genai');
require('dotenv').config();

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

const PRIMARY_MODEL = 'gemini-3.6-flash';
const FALLBACK_MODEL = 'gemini-3.1-flash-lite';
// NOTE: Google periodically retires older Gemini model IDs (this app has
// already hit that once — see server.js's history). If either of these
// starts 404ing with "no longer available", check
// https://ai.google.dev/gemini-api/docs/models for current stable model
// IDs and update both constants here — every other file imports these
// from ai.js rather than hardcoding a model name, so this is the only
// place that ever needs to change.

function isOverloadedError(err) {
  return (
    err?.status === 503 ||
    err?.error?.code === 503 ||
    /UNAVAILABLE|high demand|overloaded/i.test(err?.message || '')
  );
}

async function generateWithRetry(config, { retries = 2 } = {}) {
  let lastErr;
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      return await ai.models.generateContent(config);
    } catch (err) {
      lastErr = err;
      if (!isOverloadedError(err) || attempt === retries) break;
      const delayMs = 1000 * 2 ** attempt; // 1s, 2s, 4s...
      console.warn(
        `Gemini overloaded (attempt ${attempt + 1}/${retries + 1}), retrying in ${delayMs}ms...`
      );
      await new Promise(r => setTimeout(r, delayMs));
    }
  }

  if (isOverloadedError(lastErr) && config.model !== FALLBACK_MODEL) {
    console.warn(`Still overloaded after retries — falling back to ${FALLBACK_MODEL}`);
    try {
      return await ai.models.generateContent({ ...config, model: FALLBACK_MODEL });
    } catch (fallbackErr) {
      lastErr = fallbackErr;
    }
  }

  throw lastErr;
}

module.exports = { ai, generateWithRetry, isOverloadedError, PRIMARY_MODEL, FALLBACK_MODEL };
