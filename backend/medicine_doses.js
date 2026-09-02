// The app calls POST /confirm every time the patient taps "I took it"
// on a medicine reminder (see AlarmRingScreen). This is the ONLY thing
// that stops whatsapp_reminders.js from treating that dose as missed
// and alerting a caregiver -- so it's intentionally a very small,
// reliable endpoint: one upsert, nothing else.

const express = require('express');
const { requireAuth } = require('./auth');
const pool = require('./db');

const router = express.Router();
router.use(requireAuth);

router.post('/confirm', async (req, res) => {
  try {
    const { medicineId, scheduledFor } = req.body;
    if (!medicineId || !scheduledFor) {
      return res.status(400).json({ error: 'missing_fields' });
    }
    const scheduledDate = new Date(scheduledFor);
    if (isNaN(scheduledDate.getTime())) {
      return res.status(400).json({ error: 'invalid_scheduled_for' });
    }

    await pool.query(
      `INSERT INTO medicine_doses (user_id, medicine_id, scheduled_for, taken_at)
       VALUES ($1,$2,$3,now())
       ON CONFLICT (medicine_id, scheduled_for) DO UPDATE SET taken_at = now()`,
      [req.userId, medicineId, scheduledDate.toISOString()]
    );
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'confirm_failed' });
  }
});

module.exports = router;
