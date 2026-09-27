// Renders the "Sathi Emergency Medical Card" PDF — a compact, one-page
// summary a patient can show a family member or an ER doctor without
// needing to unlock the app or scroll through screens. Deliberately laid
// out to be readable in a hurry: big blood-group badge, red allergy box
// up top (the single highest-stakes field in an emergency), then current
// medicines and chronic conditions.
//
// IMPORTANT: every field on this PDF except `aiSummary` is the patient's
// own data, copied verbatim from their profile/medicines — never
// AI-generated. Only the one-paragraph summary at the bottom is written
// by Gemini (see EMERGENCY_CARD_PROMPT in emergency_card.js), and even
// that is explicitly instructed to just restate the data in plain
// sentences, not add anything. In an emergency-card context, a
// hallucinated allergy or medicine is far more dangerous than a
// hallucinated lab-report summary, so nothing safety-critical here is
// left to the model.
const PDFDocument = require('pdfkit');

const SATHI_BLUE = '#3D5AFE';
const SATHI_BLUE_DARK = '#1A237E';
const TEXT_GRAY = '#555555';
const BORDER_GRAY = '#DDDDDD';
const ALERT_BG = '#FFEBEE';
const ALERT_BORDER = '#E53935';
const ALERT_TEXT = '#B71C1C';

/**
 * @param {object} data
 * @param {string} data.patientName
 * @param {number|null} data.age
 * @param {string|null} data.gender
 * @param {string|null} data.bloodGroup
 * @param {string|null} data.allergies - free text, comma-separated
 * @param {string|null} data.chronicConditions - free text, comma-separated
 * @param {Array<{name:string, dosage:string, times:string}>} data.medicines
 * @param {string} data.aiSummary - short plain-language recap
 * @param {Date} data.generatedAt
 * @returns {Promise<Buffer>}
 */
function buildEmergencyCardPdf(data) {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ margin: 40, size: 'A4', bufferPages: true });
    const chunks = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    const pageWidth = doc.page.width - doc.page.margins.left - doc.page.margins.right;

    // ---------------- Header banner ----------------
    doc.rect(0, 0, doc.page.width, 90).fill(SATHI_BLUE);
    doc.fillColor('white').font('Helvetica-Bold').fontSize(22).text('Sathi', 40, 22);
    doc.font('Helvetica-Bold').fontSize(13).text('EMERGENCY MEDICAL CARD', 40, 50);
    doc.font('Helvetica').fontSize(9).fillColor('#E3E8FF')
      .text('Show this to any family member, first responder, or doctor in an emergency.', 40, 68);
    doc.y = 108;
    doc.x = 40;

    // ---------------- Patient + blood group ----------------
    const infoY = doc.y;
    doc.font('Helvetica-Bold').fontSize(8).fillColor(TEXT_GRAY).text('PATIENT NAME', 40, infoY);
    doc.font('Helvetica-Bold').fontSize(16).fillColor('black').text(data.patientName || 'Not provided', 40, infoY + 12);

    doc.font('Helvetica-Bold').fontSize(8).fillColor(TEXT_GRAY).text('AGE / GENDER', 40, infoY + 40);
    doc.font('Helvetica').fontSize(11).fillColor('black')
      .text(`${data.age ?? '—'} / ${data.gender || '—'}`, 40, infoY + 52);

    // Blood group badge, top-right — the single field most people look
    // for first in an emergency.
    const badgeX = doc.page.width - doc.page.margins.right - 90;
    doc.roundedRect(badgeX, infoY, 90, 66, 8).fillAndStroke(SATHI_BLUE_DARK, SATHI_BLUE_DARK);
    doc.fillColor('white').font('Helvetica').fontSize(8).text('BLOOD GROUP', badgeX, infoY + 10, { width: 90, align: 'center' });
    doc.font('Helvetica-Bold').fontSize(24).text(data.bloodGroup || '—', badgeX, infoY + 24, { width: 90, align: 'center' });

    doc.y = infoY + 90;
    doc.x = 40;

    // ---------------- Allergies (highest priority) ----------------
    const allergyText = (data.allergies && data.allergies.trim()) || 'None recorded';
    const allergyBoxY = doc.y;
    const allergyBoxHeight = 46;
    doc.roundedRect(40, allergyBoxY, pageWidth, allergyBoxHeight, 6).fillAndStroke(ALERT_BG, ALERT_BORDER);
    doc.fillColor(ALERT_TEXT).font('Helvetica-Bold').fontSize(10).text('⚠ ALLERGIES', 52, allergyBoxY + 8);
    doc.font('Helvetica-Bold').fontSize(12).text(allergyText, 52, allergyBoxY + 22, { width: pageWidth - 24 });
    doc.y = allergyBoxY + allergyBoxHeight + 14;
    doc.x = 40;

    // ---------------- Chronic conditions ----------------
    doc.fillColor(SATHI_BLUE_DARK).font('Helvetica-Bold').fontSize(11).text('Chronic Conditions');
    doc.moveDown(0.2);
    doc.fillColor('black').font('Helvetica').fontSize(10)
      .text((data.chronicConditions && data.chronicConditions.trim()) || 'None recorded', { width: pageWidth });
    doc.moveDown(0.8);

    // ---------------- Current medicines ----------------
    doc.fillColor(SATHI_BLUE_DARK).font('Helvetica-Bold').fontSize(11).text('Current Medicines');
    doc.moveDown(0.3);

    if (!data.medicines || data.medicines.length === 0) {
      doc.fillColor('black').font('Helvetica').fontSize(10).text('None recorded');
    } else {
      const colWidths = [pageWidth * 0.4, pageWidth * 0.3, pageWidth * 0.3];
      const startX = doc.x;
      let y = doc.y;
      const rowHeight = 20;

      doc.rect(startX, y, pageWidth, rowHeight).fill(SATHI_BLUE_DARK);
      ['Medicine', 'Dosage', 'Times'].forEach((h, i) => {
        const x = startX + colWidths.slice(0, i).reduce((a, b) => a + b, 0);
        doc.fillColor('white').font('Helvetica-Bold').fontSize(9).text(h, x + 6, y + 6, { width: colWidths[i] - 12 });
      });
      y += rowHeight;

      data.medicines.forEach((m, idx) => {
        const bg = idx % 2 === 0 ? '#F7F9FF' : '#FFFFFF';
        doc.rect(startX, y, pageWidth, rowHeight).fill(bg);
        const cells = [m.name || '—', m.dosage || '—', m.times || '—'];
        cells.forEach((cell, i) => {
          const x = startX + colWidths.slice(0, i).reduce((a, b) => a + b, 0);
          doc.fillColor('black').font('Helvetica').fontSize(9).text(String(cell), x + 6, y + 6, { width: colWidths[i] - 12 });
        });
        y += rowHeight;
      });
      doc.rect(startX, doc.y, pageWidth, y - doc.y).stroke(BORDER_GRAY);
      doc.x = startX;
      doc.y = y + 10;
    }

    // ---------------- AI plain-language summary ----------------
    if (data.aiSummary) {
      doc.moveDown(0.4);
      doc.fillColor(SATHI_BLUE_DARK).font('Helvetica-Bold').fontSize(11).text('Quick Summary');
      doc.moveDown(0.2);
      doc.fillColor('black').font('Helvetica-Oblique').fontSize(10).text(data.aiSummary, { width: pageWidth });
    }

    // ---------------- Footer ----------------
    const range = doc.bufferedPageRange();
    for (let i = range.start; i < range.start + range.count; i++) {
      doc.switchToPage(i);
      const savedBottomMargin = doc.page.margins.bottom;
      doc.page.margins.bottom = 0;
      doc.font('Helvetica').fontSize(8).fillColor(TEXT_GRAY).text(
        `Generated by Sathi on ${data.generatedAt.toLocaleString('en-US')}`,
        40,
        doc.page.height - 40,
        { width: pageWidth, align: 'left', lineBreak: false }
      );
      doc.font('Helvetica-Oblique').fontSize(8).fillColor(TEXT_GRAY).text(
        'This card reflects information the patient entered in the Sathi app and may not be complete or current. ' +
        'Always confirm critical details with the patient or their records where possible.',
        40,
        doc.page.height - 28,
        { width: pageWidth, align: 'left', lineBreak: false }
      );
      doc.page.margins.bottom = savedBottomMargin;
    }

    doc.end();
  });
}

module.exports = { buildEmergencyCardPdf };
