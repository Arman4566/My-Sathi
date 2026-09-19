// Renders the "Sathi AI Diagnostic Report" PDF from the X-ray AI
// service's real response (see xray_ai_service/). Laid out to match the
// structure of the reference report the app owner provided (patient
// info -> clinical overview -> image quality -> findings table ->
// explainable-AI heatmap section -> disclaimer page), themed for Sathi
// instead of a generic "AI Healthcare Diagnosis System" brand.
//
// DELIBERATE DIFFERENCE FROM THE REFERENCE REPORT: no "Overall Risk:
// CRITICAL/Severe" badge. See xray_ai_service/README.md's closing note
// for the full reasoning — short version: that word implies a clinical
// judgment this unvalidated research model cannot actually make.
// Everything else — the confidence numbers, the Grad-CAM images, the
// layout — is real and shown in full.
const PDFDocument = require('pdfkit');

const SATHI_BLUE = '#3D5AFE';
const SATHI_BLUE_DARK = '#1A237E';
const TEXT_GRAY = '#555555';
const BORDER_GRAY = '#DDDDDD';
const WARN_BG = '#FFF8E1';
const WARN_BORDER = '#FFD54F';

const CONFIDENCE_BAND_EXPLANATION = {
  High: 'The model\u2019s output for this finding was strongly expressed for this image.',
  Moderate: 'The model\u2019s output for this finding was moderately expressed \u2014 worth a look, not a strong signal either way.',
  Low: 'The model\u2019s output for this finding was weak for this image.',
};

function drawSectionHeading(doc, text) {
  doc.moveDown(0.6);
  doc.fillColor(SATHI_BLUE_DARK).fontSize(13).font('Helvetica-Bold').text(text);
  doc.moveTo(doc.x, doc.y + 2).lineTo(doc.page.width - doc.page.margins.right, doc.y + 2)
    .strokeColor(BORDER_GRAY).lineWidth(1).stroke();
  doc.moveDown(0.4);
  doc.fillColor('black').font('Helvetica').fontSize(10);
}

function drawKeyValueRow(doc, pairs, colWidth) {
  const startX = doc.x;
  const startY = doc.y;
  pairs.forEach((p, i) => {
    const x = startX + i * colWidth;
    doc.font('Helvetica-Bold').fontSize(8).fillColor(TEXT_GRAY).text(p.label, x, startY, { width: colWidth - 10 });
    doc.font('Helvetica').fontSize(10).fillColor('black').text(p.value, x, startY + 12, { width: colWidth - 10 });
  });
  doc.y = startY + 34;
  doc.x = startX;
}

function drawSimpleTable(doc, headers, rows, colWidths) {
  const startX = doc.x;
  let y = doc.y;
  const rowHeight = 20;

  // Header row
  doc.rect(startX, y, colWidths.reduce((a, b) => a + b, 0), rowHeight).fill(SATHI_BLUE_DARK);
  let x = startX;
  headers.forEach((h, i) => {
    doc.fillColor('white').font('Helvetica-Bold').fontSize(9)
      .text(h, x + 6, y + 6, { width: colWidths[i] - 12 });
    x += colWidths[i];
  });
  y += rowHeight;

  rows.forEach((row, rIdx) => {
    const bg = rIdx % 2 === 0 ? '#F7F9FF' : '#FFFFFF';
    doc.rect(startX, y, colWidths.reduce((a, b) => a + b, 0), rowHeight).fill(bg);
    x = startX;
    row.forEach((cell, i) => {
      doc.fillColor('black').font('Helvetica').fontSize(9)
        .text(String(cell), x + 6, y + 6, { width: colWidths[i] - 12 });
      x += colWidths[i];
    });
    y += rowHeight;
  });

  doc.rect(startX, doc.y, colWidths.reduce((a, b) => a + b, 0), y - doc.y).stroke(BORDER_GRAY);
  doc.x = startX;
  doc.y = y + 8;
}

/**
 * @param {object} data
 * @param {string} data.reportId
 * @param {Date} data.generatedAt
 * @param {string} [data.patientName]
 * @param {string} [data.patientId]
 * @param {object} data.imageQuality  - { quality, blurScore, brightness, noise, note }
 * @param {Array<{label:string, confidence:number, confidenceBand:string}>} data.findings
 * @param {object} data.primaryFinding
 * @param {string[]} data.warnings - from the model service (e.g. "doesn't look like an X-ray")
 * @param {object} data.gradCam - { featureLayer, coveragePercent, threshold, originalPngBuffer, heatmapPngBuffer, overlayPngBuffer }
 * @param {string} data.modelId
 * @returns {Promise<Buffer>}
 */
function buildXrayReportPdf(data) {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ margin: 40, size: 'A4', bufferPages: true });
    const chunks = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    const pageWidth = doc.page.width - doc.page.margins.left - doc.page.margins.right;

    // ---------------- Header banner ----------------
    doc.rect(0, 0, doc.page.width, 90).fill(SATHI_BLUE);
    doc.fillColor('white').font('Helvetica-Bold').fontSize(22).text('Sathi', 40, 24);
    doc.font('Helvetica-Bold').fontSize(11).text('AI DIAGNOSTIC REPORT', 40, 52);
    doc.font('Helvetica').fontSize(9).fillColor('#E3E8FF')
      .text('Chest X-ray Analysis  |  Real Pretrained Model  |  Explainable AI', 40, 68);
    doc.y = 110;
    doc.x = 40;

    drawKeyValueRow(
      doc,
      [
        { label: 'REPORT ID', value: data.reportId },
        { label: 'GENERATED', value: data.generatedAt.toLocaleString('en-US') },
        { label: 'MODALITY', value: 'X-RAY (Chest)' },
      ],
      pageWidth / 3
    );

    // ---------------- Patient information ----------------
    drawSectionHeading(doc, 'Patient Information');
    drawKeyValueRow(
      doc,
      [
        { label: 'PATIENT NAME', value: data.patientName || 'Not provided' },
        { label: 'PATIENT ID', value: data.patientId || 'Not provided' },
      ],
      pageWidth / 2
    );

    // ---------------- Clinical overview ----------------
    drawSectionHeading(doc, 'Clinical Overview');
    const primary = data.primaryFinding;
    drawKeyValueRow(
      doc,
      [
        { label: 'PRIMARY FINDING (AI)', value: primary.label },
        { label: 'MODEL CONFIDENCE', value: `${(primary.confidence * 100).toFixed(1)}%` },
        { label: 'CONFIDENCE LEVEL', value: primary.confidenceBand },
      ],
      pageWidth / 3
    );
    doc.font('Helvetica').fontSize(10).fillColor('black').text(
      `Clinical impression: The AI model\u2019s single highest-scoring output for this image was ` +
      `\u201c${primary.label}\u201d at ${(primary.confidence * 100).toFixed(1)}% model confidence ` +
      `(${CONFIDENCE_BAND_EXPLANATION[primary.confidenceBand] || ''}). This describes the model\u2019s ` +
      `output only \u2014 it is not a diagnosis. See the disclaimer on the final page.`,
      { width: pageWidth }
    );
    doc.moveDown(0.5);

    if (data.warnings && data.warnings.length > 0) {
      const boxY = doc.y;
      doc.rect(40, boxY, pageWidth, 18 + data.warnings.length * 14).fill(WARN_BG).stroke(WARN_BORDER);
      doc.fillColor('#7A5B00').font('Helvetica-Bold').fontSize(9).text('Please check:', 48, boxY + 6);
      let wy = boxY + 20;
      data.warnings.forEach((w) => {
        doc.font('Helvetica').fontSize(9).fillColor('#7A5B00').text(`\u2022 ${w}`, 52, wy, { width: pageWidth - 20 });
        wy += 14;
      });
      doc.y = wy + 6;
      doc.x = 40;
    }

    // ---------------- Image quality ----------------
    drawSectionHeading(doc, 'Image Quality Assessment');
    drawSimpleTable(
      doc,
      ['Quality', 'Blur Score', 'Brightness', 'Noise'],
      [[data.imageQuality.quality, data.imageQuality.blurScore, data.imageQuality.brightness, data.imageQuality.noise]],
      [pageWidth * 0.25, pageWidth * 0.25, pageWidth * 0.25, pageWidth * 0.25]
    );
    doc.font('Helvetica-Oblique').fontSize(9).fillColor(TEXT_GRAY)
      .text(`Quality note: ${data.imageQuality.note}`, { width: pageWidth });
    doc.moveDown(0.5);
    doc.fillColor('black').font('Helvetica');

    // ---------------- AI diagnostic findings ----------------
    drawSectionHeading(doc, 'AI Diagnostic Findings (all pathologies this model checks for)');
    drawSimpleTable(
      doc,
      ['Finding', 'Confidence', 'Confidence Level'],
      data.findings.map((f) => [f.label, `${(f.confidence * 100).toFixed(1)}%`, f.confidenceBand]),
      [pageWidth * 0.5, pageWidth * 0.25, pageWidth * 0.25]
    );

    doc.font('Helvetica-Oblique').fontSize(8).fillColor(TEXT_GRAY).text(
      `Model: ${data.modelId}. These are the model\u2019s raw outputs for every pathology it was trained to ` +
      `check for, sorted by confidence \u2014 not a ranked list of "what you have." Most images will show ` +
      `several nonzero scores; that is normal for this type of model and is not itself a cause for alarm.`,
      { width: pageWidth }
    );

    // ---------------- Explainable AI (new page) ----------------
    doc.addPage();
    doc.fillColor(SATHI_BLUE_DARK).font('Helvetica-Bold').fontSize(14).text('Explainable AI \u2014 Grad-CAM', 40, 40);
    doc.moveDown(0.3);
    doc.font('Helvetica').fontSize(10).fillColor('black').text(
      `This visualization explains the model\u2019s score for "${primary.label}". ` +
      `${data.gradCam.coveragePercent.toFixed(1)}% of image pixels exceeded the heatmap visualization ` +
      `threshold (${data.gradCam.threshold}). This describes model attention only and must not be ` +
      `interpreted as disease size, extent, or severity.`,
      { width: pageWidth }
    );
    doc.moveDown(0.3);
    doc.font('Helvetica-Oblique').fontSize(9).fillColor(TEXT_GRAY).text(
      `Method: Grad-CAM (Selvaraju et al., 2017), computed from this model\u2019s real gradients and ` +
      `activations for this image. Feature layer: ${data.gradCam.featureLayer}.`,
      { width: pageWidth }
    );
    doc.moveDown(0.3);
    doc.font('Helvetica').fontSize(9).fillColor('black').text(
      'How to read the map: warmer colors (yellow/red) indicate relatively stronger model attention for ' +
      'the finding above; cooler colors indicate lower attention. The colored area is not proof that ' +
      'tissue is diseased.',
      { width: pageWidth }
    );

    doc.moveDown(0.8);
    const imgWidth = (pageWidth - 20) / 3;
    const imgY = doc.y;
    const labels = ['Original Scan', 'Heatmap Only', 'Heatmap Overlay'];
    [data.gradCam.originalPngBuffer, data.gradCam.heatmapPngBuffer, data.gradCam.overlayPngBuffer].forEach((buf, i) => {
      const x = 40 + i * (imgWidth + 10);
      doc.font('Helvetica-Bold').fontSize(9).fillColor(SATHI_BLUE_DARK).text(labels[i], x, imgY, { width: imgWidth });
      doc.image(buf, x, imgY + 16, { width: imgWidth, height: imgWidth });
    });
    doc.y = imgY + 16 + imgWidth + 16;
    doc.x = 40;

    doc.font('Helvetica-Oblique').fontSize(9).fillColor(TEXT_GRAY).text(
      `Heatmap interpretation for this report: the colored region identifies where the model was most ` +
      `sensitive while computing the score for "${primary.label}". A clinician should compare this map ` +
      `with the original image, patient symptoms, examination findings, and other tests before drawing ` +
      `any conclusion.`,
      { width: pageWidth }
    );

    // ---------------- Disclaimer page ----------------
    doc.addPage();
    doc.rect(0, 0, doc.page.width, 70).fill(SATHI_BLUE);
    doc.fillColor('white').font('Helvetica-Bold').fontSize(18).text('IMPORTANT MEDICAL DISCLAIMER', 40, 26);

    doc.y = 100;
    doc.x = 40;
    const discBoxY = doc.y;
    doc.rect(40, discBoxY, pageWidth, 150).fill(WARN_BG).stroke(WARN_BORDER);
    doc.fillColor('#5B4600').font('Helvetica').fontSize(10).text(
      'This report is generated by an AI system using a pretrained, research-grade chest X-ray ' +
      'classification model. It is not a definitive diagnosis and must not replace examination, ' +
      'interpretation, or judgment by a qualified physician, radiologist, or other licensed healthcare ' +
      'professional. The model is not FDA/CE cleared or clinically validated, and its outputs may be ' +
      'affected by image quality, dataset bias, and clinical context that is not available to the software. ' +
      'All findings, confidence levels, and suggested next steps must be independently reviewed before any ' +
      'clinical decision or treatment is made.',
      { x: 48, y: discBoxY + 8, width: pageWidth - 16, lineGap: 3 }
    );

    doc.y = discBoxY + 160;
    doc.x = 40;
    doc.fillColor('black').font('Helvetica-Bold').fontSize(10).text('Report status: ', { continued: true });
    doc.font('Helvetica').text('AI-generated decision-support output \u2014 physician/radiologist review required.');

    doc.moveDown(1);
    doc.font('Helvetica-Oblique').fontSize(9).fillColor(TEXT_GRAY).text(
      'Sathi AI Diagnostic Report is a decision-support feature and is not a substitute for professional ' +
      'medical advice, diagnosis, or treatment. Always seek the advice of your physician or other qualified ' +
      'health provider with any questions you may have regarding a medical condition.'
    );

    // Footer on every page. Temporarily zeroing the bottom margin here
    // is a deliberate, known pdfkit workaround: text() auto-inserts a
    // new page if a write would land inside the bottom margin, which is
    // exactly where a footer lives by definition — without this, each
    // footer call was silently appending a blank extra page (caught by
    // actually rendering this PDF and counting 9 pages instead of 3).
    const range = doc.bufferedPageRange();
    for (let i = range.start; i < range.start + range.count; i++) {
      doc.switchToPage(i);
      const savedBottomMargin = doc.page.margins.bottom;
      doc.page.margins.bottom = 0;
      doc.font('Helvetica').fontSize(8).fillColor(TEXT_GRAY).text(
        'Sathi AI Diagnostic Report',
        40,
        doc.page.height - 30,
        { width: pageWidth / 2, align: 'left', lineBreak: false }
      );
      doc.text(`Page ${i - range.start + 1} of ${range.count}`, doc.page.width - 40 - pageWidth / 2, doc.page.height - 30, {
        width: pageWidth / 2,
        align: 'right',
        lineBreak: false,
      });
      doc.page.margins.bottom = savedBottomMargin;
    }

    doc.end();
  });
}

module.exports = { buildXrayReportPdf };
