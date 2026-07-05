// WORKED EXAMPLE: cloud-synced medicines, scoped per user via requireAuth.
// The Flutter app does NOT call this yet (medicines still live in local
// SQLite only — see README "What's cloud-synced vs. what's still local").
// This file exists so extending the same pattern to appointments,
// prescriptions, medical_reports, and health_records is a copy-paste job
// rather than a from-scratch design.

const express = require('express');
const { requireAuth } = require('./auth');
const pool = require('./db');

const router = express.Router();
router.use(requireAuth);

function toJson(row) {
  return {
    id: row.id,
    name: row.name,
    dosage: row.dosage,
    instructions: row.instructions,
    times: row.times,
    startDate: row.start_date,
    endDate: row.end_date,
    frequency: row.frequency,
    customDays: row.custom_days,
    active: row.active,
    photoPath: row.photo_path,
    prescribedBy: row.prescribed_by,
  };
}

router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM medicines WHERE user_id = $1 AND active = true ORDER BY created_at DESC',
      [req.userId]
    );
    res.json({ medicines: result.rows.map(toJson) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'fetch_failed' });
  }
});

router.post('/', async (req, res) => {
  try {
    const { name, dosage, instructions, times, startDate, endDate, frequency, customDays, photoPath, prescribedBy } = req.body;
    const result = await pool.query(
      `INSERT INTO medicines
         (user_id, name, dosage, instructions, times, start_date, end_date, frequency, custom_days, photo_path, prescribed_by)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING *`,
      [req.userId, name, dosage, instructions, times, startDate, endDate, frequency, customDays, photoPath, prescribedBy]
    );
    res.json({ medicine: toJson(result.rows[0]) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'create_failed' });
  }
});

router.put('/:id', async (req, res) => {
  try {
    const { name, dosage, instructions, times, startDate, endDate, frequency, customDays, active, photoPath, prescribedBy } = req.body;
    const result = await pool.query(
      `UPDATE medicines SET
         name = COALESCE($1, name),
         dosage = COALESCE($2, dosage),
         instructions = COALESCE($3, instructions),
         times = COALESCE($4, times),
         start_date = COALESCE($5, start_date),
         end_date = COALESCE($6, end_date),
         frequency = COALESCE($7, frequency),
         custom_days = COALESCE($8, custom_days),
         active = COALESCE($9, active),
         photo_path = COALESCE($10, photo_path),
         prescribed_by = COALESCE($11, prescribed_by)
       WHERE id = $12 AND user_id = $13 RETURNING *`,
      [name, dosage, instructions, times, startDate, endDate, frequency, customDays, active, photoPath, prescribedBy, req.params.id, req.userId]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'not_found' });
    res.json({ medicine: toJson(result.rows[0]) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'update_failed' });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM medicines WHERE id = $1 AND user_id = $2', [
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
