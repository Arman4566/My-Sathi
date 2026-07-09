// Cloud-synced health log entries. Same pattern as medicines.js.

const express = require('express');
const { requireAuth } = require('./auth');
const pool = require('./db');

const router = express.Router();
router.use(requireAuth);

function toJson(row) {
  return {
    id: row.id,
    date: row.date,
    weightKg: row.weight_kg,
    bloodPressure: row.blood_pressure,
    sugarLevel: row.sugar_level,
    notes: row.notes,
  };
}

router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM health_records WHERE user_id = $1 ORDER BY date DESC',
      [req.userId]
    );
    res.json({ records: result.rows.map(toJson) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'fetch_failed' });
  }
});

router.post('/', async (req, res) => {
  try {
    const { id, date, weightKg, bloodPressure, sugarLevel, notes } = req.body;
    if (!id) return res.status(400).json({ error: 'missing_id' });

    const result = await pool.query(
      `INSERT INTO health_records (id, user_id, date, weight_kg, blood_pressure, sugar_level, notes)
       VALUES ($1,$2,$3,$4,$5,$6,$7)
       ON CONFLICT (id) DO UPDATE SET
         date = EXCLUDED.date,
         weight_kg = EXCLUDED.weight_kg,
         blood_pressure = EXCLUDED.blood_pressure,
         sugar_level = EXCLUDED.sugar_level,
         notes = EXCLUDED.notes
       RETURNING *`,
      [id, req.userId, date, weightKg, bloodPressure, sugarLevel, notes]
    );
    res.json({ record: toJson(result.rows[0]) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'create_failed' });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM health_records WHERE id = $1 AND user_id = $2', [
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
