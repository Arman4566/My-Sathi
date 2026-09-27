// Cloud-synced structured lab test values (the numeric readings behind
// the app's "Lab Trends" charts). Same pattern as medical_reports.js —
// each row is one test result (e.g. "Hemoglobin: 13.2") tied to the
// report it came from, so the app can pull the full history back on a
// new device and re-chart it.

const express = require('express');
const { requireAuth } = require('./auth');
const pool = require('./db');

const router = express.Router();
router.use(requireAuth);

function toJson(row) {
  return {
    id: row.id,
    reportId: row.report_id,
    testName: row.test_name,
    value: row.value,
    unit: row.unit,
    refLow: row.ref_low,
    refHigh: row.ref_high,
    date: row.date,
  };
}

router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM lab_values WHERE user_id = $1 ORDER BY date ASC',
      [req.userId]
    );
    res.json({ values: result.rows.map(toJson) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'fetch_failed' });
  }
});

router.post('/', async (req, res) => {
  try {
    const { id, reportId, testName, value, unit, refLow, refHigh, date } = req.body;
    if (!id) return res.status(400).json({ error: 'missing_id' });

    const result = await pool.query(
      `INSERT INTO lab_values (id, user_id, report_id, test_name, value, unit, ref_low, ref_high, date)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
       ON CONFLICT (id) DO UPDATE SET
         report_id = EXCLUDED.report_id,
         test_name = EXCLUDED.test_name,
         value = EXCLUDED.value,
         unit = EXCLUDED.unit,
         ref_low = EXCLUDED.ref_low,
         ref_high = EXCLUDED.ref_high,
         date = EXCLUDED.date
       RETURNING *`,
      [id, req.userId, reportId, testName, value, unit, refLow ?? null, refHigh ?? null, date]
    );
    res.json({ value: toJson(result.rows[0]) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'create_failed' });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM lab_values WHERE id = $1 AND user_id = $2', [
      req.params.id,
      req.userId,
    ]);
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'delete_failed' });
  }
});

// Deletes every lab value tied to one report — called when a report
// itself is deleted, so a removed report's numbers don't keep showing
// up in trend charts.
router.delete('/by-report/:reportId', async (req, res) => {
  try {
    await pool.query('DELETE FROM lab_values WHERE report_id = $1 AND user_id = $2', [
      req.params.reportId,
      req.userId,
    ]);
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'delete_failed' });
  }
});

module.exports = router;
