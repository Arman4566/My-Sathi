// Cloud-synced medical reports (lab results, scans, etc.). Same pattern
// as medicines.js.

const express = require('express');
const { requireAuth } = require('./auth');
const pool = require('./db');

const router = express.Router();
router.use(requireAuth);

function toJson(row) {
  return {
    id: row.id,
    title: row.title,
    filePath: row.file_path,
    rawText: row.raw_text,
    summary: row.summary,
    uploadedDate: row.uploaded_date,
  };
}

router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM medical_reports WHERE user_id = $1 ORDER BY uploaded_date DESC',
      [req.userId]
    );
    res.json({ reports: result.rows.map(toJson) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'fetch_failed' });
  }
});

router.post('/', async (req, res) => {
  try {
    const { id, title, filePath, rawText, summary, uploadedDate } = req.body;
    if (!id) return res.status(400).json({ error: 'missing_id' });

    const result = await pool.query(
      `INSERT INTO medical_reports (id, user_id, title, file_path, raw_text, summary, uploaded_date)
       VALUES ($1,$2,$3,$4,$5,$6,$7)
       ON CONFLICT (id) DO UPDATE SET
         title = EXCLUDED.title,
         file_path = EXCLUDED.file_path,
         raw_text = EXCLUDED.raw_text,
         summary = EXCLUDED.summary,
         uploaded_date = EXCLUDED.uploaded_date
       RETURNING *`,
      [id, req.userId, title, filePath, rawText, summary, uploadedDate]
    );
    res.json({ report: toJson(result.rows[0]) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'create_failed' });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM medical_reports WHERE id = $1 AND user_id = $2', [
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
