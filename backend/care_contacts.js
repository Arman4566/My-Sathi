// Caregiver/family contacts who get WhatsApp alerts when the patient
// looks like they've missed a medicine dose, or shortly before an
// appointment. Same client-supplied-id upsert pattern as medicines.js.
// See whatsapp_reminders.js for the poller that actually sends messages
// to these numbers.

const express = require('express');
const { requireAuth } = require('./auth');
const pool = require('./db');

const router = express.Router();
router.use(requireAuth);

function toJson(row) {
  return {
    id: row.id,
    name: row.name,
    phone: row.phone,
    notifyMissedMedicine: row.notify_missed_medicine,
    notifyBeforeAppointment: row.notify_before_appointment,
  };
}

router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM care_contacts WHERE user_id = $1 ORDER BY created_at ASC',
      [req.userId]
    );
    res.json({ contacts: result.rows.map(toJson) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'fetch_failed' });
  }
});

router.post('/', async (req, res) => {
  try {
    const { id, name, phone, notifyMissedMedicine, notifyBeforeAppointment } = req.body;
    if (!id || !phone) return res.status(400).json({ error: 'missing_fields' });

    const result = await pool.query(
      `INSERT INTO care_contacts (id, user_id, name, phone, notify_missed_medicine, notify_before_appointment)
       VALUES ($1,$2,$3,$4,$5,$6)
       ON CONFLICT (id) DO UPDATE SET
         name = EXCLUDED.name,
         phone = EXCLUDED.phone,
         notify_missed_medicine = EXCLUDED.notify_missed_medicine,
         notify_before_appointment = EXCLUDED.notify_before_appointment
       RETURNING *`,
      [id, req.userId, name || null, phone, notifyMissedMedicine ?? true, notifyBeforeAppointment ?? true]
    );
    res.json({ contact: toJson(result.rows[0]) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'create_failed' });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM care_contacts WHERE id = $1 AND user_id = $2', [
      req.params.id,
      req.userId,
    ]);
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'delete_failed' });
  }
});

module.exports = router;
