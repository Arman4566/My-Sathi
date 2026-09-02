// WhatsApp caregiver notifications:
//   1) "This medicine dose looks missed" -- sent if a scheduled dose
//      time has passed by MISSED_DOSE_ALERT_MINUTES with no "I took it"
//      confirmation from the app.
//   2) "Appointment coming up in 30 minutes" -- sent once per
//      appointment, APPOINTMENT_REMINDER_MINUTES before its date_time.
//
// Runs as a background poller (like appointment_calls.js's scheduled-call
// poller) so both fire even if the patient's phone/app isn't open —
// that's the whole point of notifying someone else.
//
// SETUP REQUIRED (see .env.example):
// - The same TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN used for AI phone
//   calls.
// - TWILIO_WHATSAPP_FROM: a WhatsApp-enabled Twilio sender number.
//   Twilio's free WhatsApp Sandbox works for testing, but EVERY
//   recipient number must first send the sandbox's "join <code>"
//   message to it once — WhatsApp doesn't allow a business sender to
//   message a number that hasn't opted in first. For real caregivers
//   who haven't done that, this call silently fails; check the backend
//   logs. Moving to an approved WhatsApp Business sender (after
//   template approval) lifts that restriction.
//
// CONFIGURABLE (both optional, see .env.example):
// - MEDICINE_MISSED_DOSE_ALERT_MINUTES (default 30)
// - APPOINTMENT_REMINDER_MINUTES_BEFORE (default 30)

const twilio = require('twilio');
const pool = require('./db');

const MISSED_DOSE_ALERT_MINUTES = parseInt(process.env.MEDICINE_MISSED_DOSE_ALERT_MINUTES || '30', 10);
const APPOINTMENT_REMINDER_MINUTES = parseInt(process.env.APPOINTMENT_REMINDER_MINUTES_BEFORE || '30', 10);
const POLL_INTERVAL_MS = 5 * 60 * 1000; // 5 min is plenty of resolution for a 30-min-granularity feature
const DOSE_LOOKBACK_HOURS = 6; // ignore doses older than this so a long-untouched medicine can't spam alerts forever

function twilioClient() {
  const sid = process.env.TWILIO_ACCOUNT_SID;
  const token = process.env.TWILIO_AUTH_TOKEN;
  if (!sid || !token) return null;
  return twilio(sid, token);
}

async function sendWhatsApp(toPhone, body) {
  const client = twilioClient();
  const from = process.env.TWILIO_WHATSAPP_FROM;
  if (!client || !from) {
    console.warn('[whatsapp_reminders] Skipped — Twilio/TWILIO_WHATSAPP_FROM not configured. Would have sent:', body);
    return false;
  }
  try {
    await client.messages.create({
      from: `whatsapp:${from}`,
      to: `whatsapp:${toPhone}`,
      body,
    });
    return true;
  } catch (err) {
    console.error(`[whatsapp_reminders] Send to ${toPhone} failed:`, err.message);
    return false;
  }
}

// Mirrors the Flutter app's NotificationService._nextOccurrenceForMedicine
// (see notification_service.dart), but walks backward from now to find
// recent PAST occurrences within the lookback window, since this is
// checking for doses that may have been missed rather than scheduling
// the next one.
function recentOccurrences(medicine, timeStr) {
  const parts = timeStr.split(':');
  const hour = parseInt(parts[0], 10);
  const minute = parseInt(parts[1], 10);
  if (isNaN(hour) || isNaN(minute)) return [];

  const now = new Date();
  const results = [];
  for (let daysAgo = 0; daysAgo <= 1; daysAgo++) {
    const candidate = new Date(now);
    candidate.setDate(candidate.getDate() - daysAgo);
    candidate.setHours(hour, minute, 0, 0);
    if (candidate > now) continue; // hasn't happened yet
    if (now - candidate > DOSE_LOOKBACK_HOURS * 3600 * 1000) continue; // too old

    if (medicine.frequency === 'custom') {
      const customDays = (medicine.custom_days || '').split(',').filter(Boolean).map(Number);
      // JS Date.getDay(): 0=Sunday..6=Saturday. The app's DateTime.weekday: 1=Monday..7=Sunday.
      const weekday = candidate.getDay() === 0 ? 7 : candidate.getDay();
      if (!customDays.includes(weekday)) continue;
    }
    if (medicine.start_date && candidate < new Date(medicine.start_date)) continue;
    if (medicine.end_date && candidate > new Date(medicine.end_date)) continue;

    results.push(candidate);
  }
  return results;
}

async function checkMissedDoses() {
  const medsResult = await pool.query(
    `SELECT m.*, u.name AS user_name FROM medicines m
     JOIN users u ON u.id = m.user_id
     WHERE m.active = true`
  );

  for (const medicine of medsResult.rows) {
    const times = (medicine.times || '').split(',').filter(Boolean);
    for (const timeStr of times) {
      for (const scheduledFor of recentOccurrences(medicine, timeStr)) {
        const overdueMs = Date.now() - scheduledFor.getTime();
        if (overdueMs < MISSED_DOSE_ALERT_MINUTES * 60 * 1000) continue; // not overdue enough yet

        const doseResult = await pool.query(
          `SELECT * FROM medicine_doses WHERE medicine_id = $1 AND scheduled_for = $2`,
          [medicine.id, scheduledFor.toISOString()]
        );
        const dose = doseResult.rows[0];
        if (dose?.taken_at) continue; // confirmed taken
        if (dose?.missed_alert_sent_at) continue; // already alerted for this exact slot

        const contactsResult = await pool.query(
          `SELECT * FROM care_contacts WHERE user_id = $1 AND notify_missed_medicine = true`,
          [medicine.user_id]
        );
        if (contactsResult.rows.length === 0) continue; // no one configured to tell

        const timeLabel = scheduledFor.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
        const body =
          `⚠️ Medicine reminder: ${medicine.user_name} may have missed their ` +
          `${medicine.name}${medicine.dosage ? ` (${medicine.dosage})` : ''} dose ` +
          `scheduled for ${timeLabel}. Please check in with them.`;

        for (const contact of contactsResult.rows) {
          await sendWhatsApp(contact.phone, body);
        }

        if (dose) {
          await pool.query(`UPDATE medicine_doses SET missed_alert_sent_at = now() WHERE id = $1`, [dose.id]);
        } else {
          await pool.query(
            `INSERT INTO medicine_doses (user_id, medicine_id, scheduled_for, missed_alert_sent_at)
             VALUES ($1,$2,$3,now())
             ON CONFLICT (medicine_id, scheduled_for) DO UPDATE SET missed_alert_sent_at = now()`,
            [medicine.user_id, medicine.id, scheduledFor.toISOString()]
          );
        }
      }
    }
  }
}

async function checkUpcomingAppointmentReminders() {
  // A window rather than an exact-minute match, so a slow or delayed
  // poll tick still catches every appointment instead of skipping it.
  const windowStart = new Date(Date.now() + (APPOINTMENT_REMINDER_MINUTES - 5) * 60 * 1000);
  const windowEnd = new Date(Date.now() + (APPOINTMENT_REMINDER_MINUTES + 5) * 60 * 1000);

  const result = await pool.query(
    `SELECT a.*, u.name AS user_name FROM appointments a
     JOIN users u ON u.id = a.user_id
     WHERE a.date_time BETWEEN $1 AND $2 AND a.whatsapp_reminder_sent_at IS NULL`,
    [windowStart.toISOString(), windowEnd.toISOString()]
  );

  for (const appt of result.rows) {
    const contactsResult = await pool.query(
      `SELECT * FROM care_contacts WHERE user_id = $1 AND notify_before_appointment = true`,
      [appt.user_id]
    );
    if (contactsResult.rows.length > 0) {
      const timeLabel = new Date(appt.date_time).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
      const body =
        `📅 Reminder: ${appt.user_name}'s appointment with ` +
        `${appt.doctor_name ? `Dr. ${appt.doctor_name}` : 'their doctor'}` +
        `${appt.location ? ` at ${appt.location}` : ''} is coming up at ${timeLabel} ` +
        `(in about ${APPOINTMENT_REMINDER_MINUTES} minutes).`;
      for (const contact of contactsResult.rows) {
        await sendWhatsApp(contact.phone, body);
      }
    }
    // Marked as sent regardless of whether any contact was configured,
    // so an appointment with no caregiver contacts doesn't get
    // re-evaluated every poll tick for the rest of its window.
    await pool.query(`UPDATE appointments SET whatsapp_reminder_sent_at = now() WHERE id = $1`, [appt.id]);
  }
}

let pollerRunning = false;
async function pollReminders() {
  if (pollerRunning) return; // don't overlap if a previous tick is still working
  pollerRunning = true;
  try {
    await checkMissedDoses();
    await checkUpcomingAppointmentReminders();
  } catch (err) {
    console.error('[whatsapp_reminders] Poll failed:', err);
  } finally {
    pollerRunning = false;
  }
}

function startWhatsAppReminderPoller() {
  setInterval(pollReminders, POLL_INTERVAL_MS);
  setTimeout(pollReminders, 10 * 1000); // small delay so it doesn't compete with server startup
}

module.exports = { startWhatsAppReminderPoller };
