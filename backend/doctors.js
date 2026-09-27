// "Find nearby doctors" — two steps chained together:
//
//   1. AI (Gemini, same client as ai.js) reads the patient's described
//      medical condition/symptom and maps it to ONE specialist type from
//      a fixed list (e.g. "Cardiologist"). This is deliberately just a
//      *category* lookup, not a diagnosis — the same "never diagnose"
//      boundary the chatbot follows in server.js applies here too. The
//      patient can also skip this entirely and pass `specialty` directly
//      (used when they tap one of the quick-pick chips in the app
//      instead of typing a symptom).
//
//   2. OpenStreetMap's Overpass API looks up real doctors/clinics/
//      hospitals near the patient's given coordinates — no API key or
//      billing account needed, since Overpass is a free public service
//      over OSM's community-maintained map data.
//
//      IMPORTANT DIFFERENCE FROM GOOGLE PLACES: OSM has no built-in
//      rating/review system, so there is no equivalent to Google's
//      "minimum rating / minimum review count" filter — that data simply
//      doesn't exist in OSM. Instead, results are ranked by distance
//      from the patient (closest first), and we only show places that
//      are actually tagged as a name-bearing medical facility so the
//      list stays meaningful rather than an unfiltered raw dump.
//
// No env var is required for this feature anymore. Nothing here is
// persisted to the database — this is a stateless proxy + filter, same
// spirit as parse-prescription/summarize-report in server.js.
//
// Be a good citizen of the free Overpass API: requests are sequential
// (one per search), and we identify ourselves with a descriptive
// User-Agent as the Overpass usage policy asks
// (https://operations.osmfoundation.org/policies/overpass/).

const express = require('express');
const { requireAuth } = require('./auth');
const { generateWithRetry, isOverloadedError, isQuotaExceededError, PRIMARY_MODEL } = require('./ai');

const router = express.Router();
router.use(requireAuth);

// Keeping this to a fixed, known-good list (rather than letting the model
// invent free-text specialties) means step 2's tag/name matching is
// always searching for a real, recognizable specialty term.
const SPECIALIST_TYPES = [
  'General Physician',
  'Cardiologist',
  'Dermatologist',
  'Pediatrician',
  'Gynecologist',
  'Orthopedist',
  'ENT Specialist',
  'Neurologist',
  'Psychiatrist',
  'Dentist',
  'Ophthalmologist',
  'Pulmonologist',
  'Gastroenterologist',
  'Endocrinologist',
  'Urologist',
  'Nephrologist',
  'Oncologist',
  'Rheumatologist',
];

// OSM's healthcare:speciality tag (https://wiki.openstreetmap.org/wiki/Key:healthcare:speciality)
// uses its own vocabulary, which we map our fixed specialist list onto.
// Tagging is patchy in OSM, so this is used as a *ranking boost*, not a
// hard filter — see comment in scoreForSpecialist below.
const SPECIALTY_KEYWORDS = {
  'General Physician': ['general', 'family', 'gp'],
  Cardiologist: ['cardiology', 'cardiologist', 'heart'],
  Dermatologist: ['dermatology', 'dermatologist', 'skin'],
  Pediatrician: ['paediatrics', 'pediatrics', 'child'],
  Gynecologist: ['gynaecology', 'gynecology', 'obstetrics', 'women'],
  Orthopedist: ['orthopaedics', 'orthopedics', 'orthopaedic', 'bone'],
  'ENT Specialist': ['otolaryngology', 'ent', 'ear', 'nose', 'throat'],
  Neurologist: ['neurology', 'neurologist'],
  Psychiatrist: ['psychiatry', 'psychiatrist', 'mental'],
  Dentist: ['dentistry', 'dental', 'dentist'],
  Ophthalmologist: ['ophthalmology', 'eye'],
  Pulmonologist: ['pulmonology', 'lung', 'respiratory', 'chest'],
  Gastroenterologist: ['gastroenterology', 'gastro', 'digestive'],
  Endocrinologist: ['endocrinology', 'diabetes'],
  Urologist: ['urology', 'urologist'],
  Nephrologist: ['nephrology', 'kidney'],
  Oncologist: ['oncology', 'cancer'],
  Rheumatologist: ['rheumatology', 'arthritis'],
};

const SPECIALIST_PROMPT = `You help a patient figure out what KIND of\ndoctor to look for based on a symptom or medical condition they describe.\nYou are NOT diagnosing them and must never name a disease or condition in\nyour reasoning — you are only picking the right category of specialist to\nsearch for nearby, the same way a receptionist would when booking someone\nin. Choose exactly one option from this fixed list (copy it exactly,\ncharacter for character):\n${SPECIALIST_TYPES.map((s) => `- ${s}`).join('\n')}\nIf the description is general, vague, mentions multiple unrelated things,\nor you are not confident, choose \"General Physician\" — that is always a\nsafe default a patient can start with. Return ONLY valid JSON, no prose,\nno markdown fences, in this exact shape:\n{"specialist":"","reason":""}\n"reason" is one short, plain-language sentence explaining the pick to the\npatient (e.g. "Skin-related concerns are usually a good fit for a\ndermatologist.") — never mention a specific disease name in it.`;

async function pickSpecialist(medicalCondition) {
  const response = await generateWithRetry({
    model: PRIMARY_MODEL,
    contents: `Patient's description: ${medicalCondition}`,
    config: {
      systemInstruction: SPECIALIST_PROMPT,
      responseMimeType: 'application/json',
    },
  });
  const parsed = JSON.parse(response.text);
  const specialist = SPECIALIST_TYPES.includes(parsed.specialist)
    ? parsed.specialist
    : 'General Physician';
  return { specialist, reason: parsed.reason || '' };
}

const MAX_RESULTS = 15;
const OVERPASS_URL = 'https://overpass-api.de/api/interpreter';
const OVERPASS_TIMEOUT_SECONDS = 20;

function haversineMeters(lat1, lon1, lat2, lon2) {
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

// Higher score = better match for the requested specialist. Tag/name
// matches score highest; a plain "doctors"/"clinic" with no specialty
// info at all still scores low-but-nonzero so General Physician
// searches (and areas with sparse OSM tagging) still return something.
function scoreForSpecialist(tags, specialist) {
  const keywords = SPECIALTY_KEYWORDS[specialist] || [];
  const haystack = [
    tags['healthcare:speciality'],
    tags.speciality,
    tags.name,
    tags.description,
  ]
    .filter(Boolean)
    .join(' ')
    .toLowerCase();
  if (keywords.some((k) => haystack.includes(k))) return 2;
  if (specialist === 'General Physician' && (tags.amenity === 'doctors' || tags.healthcare === 'doctor')) {
    return 1;
  }
  return 0;
}

function mapsUrlFor(lat, lon) {
  return `https://www.openstreetmap.org/?mlat=${lat}&mlon=${lon}#map=18/${lat}/${lon}`;
}

function directionsUrlFor(fromLat, fromLon, toLat, toLon) {
  return `https://www.openstreetmap.org/directions?engine=fossgis_osrm_car&route=${fromLat}%2C${fromLon}%3B${toLat}%2C${toLon}`;
}

function addressFrom(tags) {
  if (tags['addr:full']) return tags['addr:full'];
  const parts = [
    [tags['addr:housenumber'], tags['addr:street']].filter(Boolean).join(' '),
    tags['addr:suburb'],
    tags['addr:city'],
  ].filter(Boolean);
  return parts.join(', ');
}

// OSM's opening_hours tag uses its own mini-language that isn't safe to
// fully parse here (getting it wrong would show a patient a clinic as
// open when it's actually closed). We only recognise the unambiguous
// "always open" case and otherwise leave this unknown rather than guess.
function isOpenNowFrom(tags) {
  if (tags.opening_hours === '24/7') return true;
  return null;
}

function phoneFrom(tags) {
  return tags.phone || tags['contact:phone'] || null;
}

async function queryOverpass(latitude, longitude, radiusMeters) {
  // Any of these tags can mark a medical facility in OSM; we cast a
  // reasonably wide net and rely on scoreForSpecialist + a name
  // requirement to keep the results relevant.
  const query = `
    [out:json][timeout:${OVERPASS_TIMEOUT_SECONDS}];
    (
      node["amenity"~"^(doctors|clinic|hospital)$"](around:${radiusMeters},${latitude},${longitude});
      way["amenity"~"^(doctors|clinic|hospital)$"](around:${radiusMeters},${latitude},${longitude});
      node["healthcare"~"^(doctor|clinic|hospital|centre)$"](around:${radiusMeters},${latitude},${longitude});
      way["healthcare"~"^(doctor|clinic|hospital|centre)$"](around:${radiusMeters},${latitude},${longitude});
    );
    out center tags;
  `;

  const response = await fetch(OVERPASS_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      // Overpass's usage policy asks clients to identify themselves.
      'User-Agent': 'PatientCareApp/1.0 (find-nearby-doctors feature)',
    },
    body: `data=${encodeURIComponent(query)}`,
  });

  if (!response.ok) {
    const err = new Error(`Overpass API returned ${response.status}`);
    err.overpassStatus = response.status;
    throw err;
  }

  const data = await response.json();
  return Array.isArray(data.elements) ? data.elements : [];
}

router.post('/nearby', async (req, res) => {
  try {
    const { latitude, longitude, medicalCondition, specialty, radiusMeters } = req.body;
    if (typeof latitude !== 'number' || typeof longitude !== 'number') {
      return res.status(400).json({ error: 'missing_location' });
    }

    // Step 1: work out which kind of doctor to look for.
    let specialist, specialistReason;
    if (specialty && SPECIALIST_TYPES.includes(specialty)) {
      // Patient picked a specialty chip directly in the app — skip the AI
      // call entirely, both to save quota and because there's nothing to
      // infer.
      specialist = specialty;
      specialistReason = '';
    } else if (medicalCondition && medicalCondition.trim()) {
      ({ specialist, reason: specialistReason } = await pickSpecialist(medicalCondition.trim()));
    } else {
      specialist = 'General Physician';
      specialistReason = '';
    }

    // Step 2: real, nearby doctors/clinics/hospitals from OpenStreetMap,
    // ranked by specialty match then distance.
    const radius = Math.min(Math.max(radiusMeters || 5000, 500), 50000);
    let elements;
    try {
      elements = await queryOverpass(latitude, longitude, radius);
    } catch (err) {
      console.error('Overpass lookup failed:', err);
      return res.status(502).json({
        error: 'places_lookup_failed',
        message: 'Could not look up nearby doctors right now. Please try again shortly.',
      });
    }

    const withCoords = elements
      .map((el) => {
        const lat = el.lat ?? el.center?.lat;
        const lon = el.lon ?? el.center?.lon;
        return { el, lat, lon };
      })
      .filter(({ el, lat, lon }) => el.tags?.name && typeof lat === 'number' && typeof lon === 'number');

    const scored = withCoords
      .map(({ el, lat, lon }) => ({
        el,
        lat,
        lon,
        distance: haversineMeters(latitude, longitude, lat, lon),
        score: scoreForSpecialist(el.tags, specialist),
      }))
      // A score of 0 means neither this specialty's keywords nor a bare
      // "doctors" tag matched — still shown (OSM tagging is inconsistent
      // and we'd rather over-include than hide a real nearby clinic),
      // just ranked below better matches.
      .sort((a, b) => b.score - a.score || a.distance - b.distance)
      .slice(0, MAX_RESULTS);

    const doctors = scored.map(({ el, lat, lon, distance }) => ({
      placeId: `${el.type}/${el.id}`,
      name: el.tags.name,
      specialty: specialist,
      address: addressFrom(el.tags),
      isOpenNow: isOpenNowFrom(el.tags),
      distanceMeters: Math.round(distance),
      latitude: lat,
      longitude: lon,
      phone: phoneFrom(el.tags),
      mapsUrl: mapsUrlFor(lat, lon),
      directionsUrl: directionsUrlFor(latitude, longitude, lat, lon),
    }));

    res.json({
      specialist,
      specialistReason,
      radiusMeters: radius,
      doctors,
    });
  } catch (err) {
    console.error('Doctor search failed:', err);
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
    res.status(500).json({ error: 'doctor_search_failed', message: err.message });
  }
});

module.exports = router;
