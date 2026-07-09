// Cloud-synced appointments. Same pattern as medicines.js — see the
// comments there for why POST is an upsert and why id is client-supplied.

const express = require('express');
const { requireAuth } = require('./auth');
const pool = require('./db');

const router = express.Router();
router.use(requireAuth);

function toJson(row) {
  return {
    id: row.id,
    doctorName: row.doctor_name,
    location: row.location,
    dateTime: row.date_time,
    notes: row.notes,
    reminderSet: row.reminder_set,
  };
}

router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM appointments WHERE user_id = $1 ORDER BY date_time ASC',
      [req.userId]
    );
    res.json({ appointments: result.rows.map(toJson) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'fetch_failed' });
  }
});

router.post('/', async (req, res) => {
  try {
    const { id, doctorName, location, dateTime, notes, reminderSet } = req.body;
    if (!id) return res.status(400).json({ error: 'missing_id' });

    const result = await pool.query(
      `INSERT INTO appointments (id, user_id, doctor_name, location, date_time, notes, reminder_set)
       VALUES ($1,$2,$3,$4,$5,$6,$7)
       ON CONFLICT (id) DO UPDATE SET
         doctor_name = EXCLUDED.doctor_name,
         location = EXCLUDED.location,
         date_time = EXCLUDED.date_time,
         notes = EXCLUDED.notes,
         reminder_set = EXCLUDED.reminder_set
       RETURNING *`,
      [id, req.userId, doctorName, location, dateTime, notes, reminderSet ?? true]
    );
    res.json({ appointment: toJson(result.rows[0]) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'create_failed' });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM appointments WHERE id = $1 AND user_id = $2', [
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
