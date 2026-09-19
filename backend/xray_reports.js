// "Sathi AI Diagnostic Report" — chest X-ray only (see
// xray_ai_service/README.md for why ultrasound/other scans can't get
// this same treatment: there's no broadly-available real pretrained
// model for them the way there is for chest X-rays). Ultrasound/other
// scans keep using the Gemini-based plain-language "Scan Insight"
// feature in server.js's /api/analyze-scan instead.
//
// Flow: app uploads an image (base64) -> this forwards it to the
// separate xray_ai_service (real pretrained model + real Grad-CAM,
// see that folder's README) -> builds a themed PDF from the real
// response via xray_pdf.js -> stores the PDF bytes in Postgres (see
// schema.sql's xray_reports table for why bytea instead of local disk)
// -> returns both the report metadata and the PDF itself so the app
// can show/download it immediately, with no second round trip needed.
const express = require('express');
const crypto = require('crypto');
const { requireAuth } = require('./auth');
const pool = require('./db');
const { buildXrayReportPdf } = require('./xray_pdf');

const router = express.Router();
router.use(requireAuth);

function toJson(row) {
  return {
    id: row.id,
    title: row.title,
    primaryFinding: row.primary_finding,
    confidence: row.confidence,
    confidenceBand: row.confidence_band,
    modelId: row.model_id,
    createdAt: row.created_at,
  };
}

router.get('/', async (req, res) => {
  try {
    // Explicitly NOT selecting pdf_data here — it can be a few hundred
    // KB each and this is a list view; GET /:id/pdf below fetches the
    // actual bytes only when the user opens/downloads a specific report.
    const result = await pool.query(
      `SELECT id, title, primary_finding, confidence, confidence_band, model_id, created_at
       FROM xray_reports WHERE user_id = $1 ORDER BY created_at DESC`,
      [req.userId]
    );
    res.json({ reports: result.rows.map(toJson) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'fetch_failed' });
  }
});

router.get('/:id/pdf', async (req, res) => {
  try {
    const result = await pool.query(`SELECT * FROM xray_reports WHERE id = $1 AND user_id = $2`, [
      req.params.id,
      req.userId,
    ]);
    const row = result.rows[0];
    if (!row) return res.status(404).json({ error: 'not_found' });
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="${row.title || 'sathi-xray-report'}.pdf"`);
    res.send(row.pdf_data);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'fetch_failed' });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM xray_reports WHERE id = $1 AND user_id = $2', [req.params.id, req.userId]);
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'delete_failed' });
  }
});

router.post('/analyze', async (req, res) => {
  try {
    const serviceUrl = process.env.XRAY_MODEL_SERVICE_URL;
    if (!serviceUrl) {
      return res.status(503).json({
        error: 'xray_service_not_configured',
        message:
          'The chest X-ray AI model service isn\u2019t set up yet. Deploy xray_ai_service/ and set ' +
          'XRAY_MODEL_SERVICE_URL in the backend .env file (see xray_ai_service/README.md).',
      });
    }

    const { imageBase64, mimeType, patientName, patientId } = req.body;
    if (!imageBase64 || !mimeType) {
      return res.status(400).json({ error: 'missing_image' });
    }

    const imageBuffer = Buffer.from(imageBase64, 'base64');
    const form = new FormData();
    const ext = mimeType.includes('png') ? 'png' : 'jpg';
    form.append('file', new Blob([imageBuffer], { type: mimeType }), `upload.${ext}`);

    let modelResponse;
    try {
      const upstream = await fetch(`${serviceUrl.replace(/\/$/, '')}/analyze`, {
        method: 'POST',
        body: form,
        // Deliberately generous. Free-tier hosts (Render's free web
        // services included) spin down when idle and can take 50+
        // seconds just to wake up on the next request, BEFORE any
        // actual model inference time is added on top — a 60s timeout
        // here was cutting that too close and caused real, reproducible
        // "could not reach the X-ray AI model service" failures on a
        // cold instance. 170s gives real headroom above a ~50-60s cold
        // start plus a few seconds of CPU inference, while still being
        // comfortably under typical platform-level request limits
        // (~180s+ on most hosts). If you're on a paid/always-on tier
        // for the model service, this basically never gets used, so
        // there's no real downside to it being generous.
        signal: AbortSignal.timeout(170000),
      });
      if (!upstream.ok) {
        const text = await upstream.text().catch(() => '');
        console.error('X-ray model service error:', upstream.status, text);
        return res.status(502).json({
          error: 'xray_service_error',
          message: 'The X-ray model service could not analyze this image. Please try again.',
        });
      }
      modelResponse = await upstream.json();
    } catch (fetchErr) {
      console.error('Could not reach X-ray model service:', fetchErr);
      const isTimeout = fetchErr?.name === 'TimeoutError' || fetchErr?.name === 'AbortError';
      return res.status(502).json({
        error: 'xray_service_unreachable',
        message: isTimeout
          ? 'The X-ray AI model service took too long to respond \u2014 if it just woke up from being idle ' +
            '(free-tier hosting spins down when unused), please try again now that it\u2019s warm.'
          : 'Could not reach the X-ray AI model service. Please try again in a moment.',
      });
    }

    const reportId = `SATHI-${new Date().toISOString().replace(/[-:T.]/g, '').slice(0, 15)}`;
    const pdfBuffer = await buildXrayReportPdf({
      reportId,
      generatedAt: new Date(),
      patientName,
      patientId,
      imageQuality: modelResponse.imageQuality,
      findings: modelResponse.findings,
      primaryFinding: modelResponse.primaryFinding,
      warnings: modelResponse.warnings || [],
      gradCam: {
        featureLayer: modelResponse.gradCam.featureLayer,
        coveragePercent: modelResponse.gradCam.coveragePercent,
        threshold: modelResponse.gradCam.threshold,
        originalPngBuffer: Buffer.from(modelResponse.gradCam.originalPng, 'base64'),
        heatmapPngBuffer: Buffer.from(modelResponse.gradCam.heatmapPng, 'base64'),
        overlayPngBuffer: Buffer.from(modelResponse.gradCam.overlayPng, 'base64'),
      },
      modelId: modelResponse.modelId,
    });

    const id = crypto.randomUUID();
    const title = `Chest X-ray \u2014 ${modelResponse.primaryFinding.label} (${new Date().toLocaleDateString('en-US')})`;
    await pool.query(
      `INSERT INTO xray_reports (id, user_id, title, primary_finding, confidence, confidence_band, model_id, pdf_data)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
      [
        id,
        req.userId,
        title,
        modelResponse.primaryFinding.label,
        modelResponse.primaryFinding.confidence,
        modelResponse.primaryFinding.confidenceBand,
        modelResponse.modelId,
        pdfBuffer,
      ]
    );

    res.json({
      report: {
        id,
        title,
        primaryFinding: modelResponse.primaryFinding.label,
        confidence: modelResponse.primaryFinding.confidence,
        confidenceBand: modelResponse.primaryFinding.confidenceBand,
        modelId: modelResponse.modelId,
        warnings: modelResponse.warnings || [],
      },
      pdfBase64: pdfBuffer.toString('base64'),
    });
  } catch (err) {
    console.error(err);
    if (err.code === '42P01') {
      return res.status(500).json({
        error: 'missing_table',
        message: 'The xray_reports table doesn\u2019t exist yet. Re-run schema.sql against your database.',
      });
    }
    res.status(500).json({ error: 'analyze_failed', message: err.message });
  }
});

module.exports = router;
