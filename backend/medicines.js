// Cloud-synced medicines, scoped per user via requireAuth.
// IMPORTANT: the client (Flutter) always supplies `id` — the same UUID
// used in the local SQLite row — so a record has one identity across
// local storage and the cloud. POST is an upsert (ON CONFLICT DO UPDATE)
// rather than a strict "create only", because cloud_sync_service.dart
// pushes fire-and-forget and may retry; upserting makes that safe.

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
      'SELECT * FROM medicines WHERE user_id = $1 ORDER BY created_at DESC',
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
    const { id, name, dosage, instructions, times, startDate, endDate, frequency, customDays, active, photoPath, prescribedBy } = req.body;
    if (!id) return res.status(400).json({ error: 'missing_id' });

    const result = await pool.query(
      `INSERT INTO medicines
         (id, user_id, name, dosage, instructions, times, start_date, end_date, frequency, custom_days, active, photo_path, prescribed_by)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
       ON CONFLICT (id) DO UPDATE SET
         name = EXCLUDED.name,
         dosage = EXCLUDED.dosage,
         instructions = EXCLUDED.instructions,
         times = EXCLUDED.times,
         start_date = EXCLUDED.start_date,
         end_date = EXCLUDED.end_date,
         frequency = EXCLUDED.frequency,
         custom_days = EXCLUDED.custom_days,
         active = EXCLUDED.active,
         photo_path = EXCLUDED.photo_path,
         prescribed_by = EXCLUDED.prescribed_by
       RETURNING *`,
      [id, req.userId, name, dosage, instructions, times, startDate, endDate, frequency, customDays, active ?? true, photoPath, prescribedBy]
    );
    res.json({ medicine: toJson(result.rows[0]) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'create_failed' });
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
