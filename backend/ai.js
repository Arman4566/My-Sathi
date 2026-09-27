// Shared Gemini client + retry/fallback helper. Originally lived inline
// in server.js; pulled out here so appointment_calls.js (AI phone-call
// booking) can reuse the exact same retry/fallback behavior instead of
// duplicating it — see server.js's comment history for why the retry
// logic exists (503 overload handling) and why the model name matters
// (a bad hardcoded model name previously broke every AI feature at once).
const { GoogleGenAI } = require('@google/genai');
require('dotenv').config();

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

// UPDATE 2026-09-27 (again, mid-hackathon): gemini-2.5-flash just came back
// 404 "no longer available to new users" — Google has fully retired the
// whole 2.5 generation ahead of schedule, not just the quota-limited 3.6
// pair from earlier today. Google's own error message points at
// gemini-3.8-flash, but that model's free tier is ALSO capped at a tiny
// 20 requests/day — the exact same problem we just had. gemini-3.5-flash-lite
// has a 500 requests/day free tier (25x more headroom), so it's PRIMARY for
// the demo; gemini-3.8-flash is FALLBACK for quality/overload cases where
// Flash-Lite alone isn't enough — its quota is separate and untouched.
const PRIMARY_MODEL = 'gemini-3.5-flash-lite';
const FALLBACK_MODEL = 'gemini-3.8-flash';
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

// Quota/rate-limit errors (429 RESOURCE_EXHAUSTED) are a DIFFERENT failure
// mode from a 503 overload and were previously not detected at all — they
// fell through to the generic 500 handler in every route below, so every
// AI feature just looked "broken" with no clue why.
// UPDATE 2026-09-27: the error body confirms quota is tracked per
// PROJECT+MODEL ("GenerateRequestsPerDayPerProjectPerModel-FreeTier"), not
// shared across models — so unlike an overload, falling back to a
// DIFFERENT model on quota-exceeded is actually useful (it has its own
// untouched daily bucket) and generateWithRetry does that below. Instant
// per-request retrying still doesn't help (it's a daily cap, not a
// per-minute one), so this stays out of the retry loop itself.
function isQuotaExceededError(err) {
  return (
    err?.status === 429 ||
    err?.error?.code === 429 ||
    /RESOURCE_EXHAUSTED|quota|rate limit/i.test(err?.message || '')
  );
}

// Added after gemini-2.5-flash got retired mid-hackathon with zero warning
// (404 "no longer available to new users"). If PRIMARY_MODEL itself gets
// retired again the same way, fail over to FALLBACK_MODEL instead of every
// AI feature going dark — cheap insurance on a day models keep moving.
function isModelUnavailableError(err) {
  return (
    err?.status === 404 ||
    err?.error?.code === 404 ||
    /NOT_FOUND|no longer available/i.test(err?.message || '')
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

  if (isModelUnavailableError(lastErr) && config.model !== FALLBACK_MODEL) {
    console.warn(`${config.model} unavailable/retired — falling back to ${FALLBACK_MODEL}`);
    try {
      return await ai.models.generateContent({ ...config, model: FALLBACK_MODEL });
    } catch (fallbackErr) {
      lastErr = fallbackErr;
    }
  }

  if (isQuotaExceededError(lastErr) && config.model !== FALLBACK_MODEL) {
    console.warn(`Quota exceeded on ${config.model} — falling back to ${FALLBACK_MODEL} (separate quota bucket)`);
    try {
      return await ai.models.generateContent({ ...config, model: FALLBACK_MODEL });
    } catch (fallbackErr) {
      lastErr = fallbackErr;
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

module.exports = {
  ai,
  generateWithRetry,
  isOverloadedError,
  isQuotaExceededError,
  isModelUnavailableError,
  PRIMARY_MODEL,
  FALLBACK_MODEL,
};
