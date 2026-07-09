// Cloud-synced prescriptions. Same pattern as medicines.js. Note:
// imagePath only makes sense on the device that created it — see the
// comment in schema.sql.

const express = require('express');
const { requireAuth } = require('./auth');
const pool = require('./db');

const router = express.Router();
router.use(requireAuth);

function toJson(row) {
  return {
    id: row.id,
    imagePath: row.image_path,
    rawText: row.raw_text,
    doctorName: row.doctor_name,
    dateAdded: row.date_added,
    notes: row.notes,
  };
}

router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM prescriptions WHERE user_id = $1 ORDER BY date_added DESC',
      [req.userId]
    );
    res.json({ prescriptions: result.rows.map(toJson) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'fetch_failed' });
  }
});

router.post('/', async (req, res) => {
  try {
    const { id, imagePath, rawText, doctorName, dateAdded, notes } = req.body;
    if (!id) return res.status(400).json({ error: 'missing_id' });

    const result = await pool.query(
      `INSERT INTO prescriptions (id, user_id, image_path, raw_text, doctor_name, date_added, notes)
       VALUES ($1,$2,$3,$4,$5,$6,$7)
       ON CONFLICT (id) DO UPDATE SET
         image_path = EXCLUDED.image_path,
         raw_text = EXCLUDED.raw_text,
         doctor_name = EXCLUDED.doctor_name,
         date_added = EXCLUDED.date_added,
         notes = EXCLUDED.notes
       RETURNING *`,
      [id, req.userId, imagePath, rawText, doctorName, dateAdded, notes]
    );
    res.json({ prescription: toJson(result.rows[0]) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'create_failed' });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM prescriptions WHERE id = $1 AND user_id = $2', [
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
