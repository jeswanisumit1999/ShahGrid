import PDFDocument from 'pdfkit';

type PDoc = InstanceType<typeof PDFDocument>;

function fmtDate(d: Date | string): string {
  const dt = new Date(d);
  const dd = String(dt.getDate()).padStart(2, '0');
  const mm = String(dt.getMonth() + 1).padStart(2, '0');
  const yyyy = String(dt.getFullYear());
  return `${dd}/${mm}/${yyyy}`;
}

function fmtAmt(n: number): string {
  return n.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function entryLabel(type: string, delta: number): string {
  switch (type) {
    case 'order_debit':        return 'Order Placed';
    case 'item_added':         return 'Item Added';
    case 'qty_adjusted':       return delta > 0 ? 'Qty Increased' : 'Qty Decreased';
    case 'payment_credit':     return 'Payment Received';
    case 'return_credit':      return 'Return Credit';
    case 'delivery_adjustment':return 'Delivery Adjusted';
    case 'shipment_return':    return 'Shipment Returned';
    case 'opening_balance':    return 'Opening Balance';
    default:                   return type.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
  }
}

// ── Layout (A4) ───────────────────────────────────────────────────────────────

const PW = 595;
const PH = 842;
const ML = 35;
const MR = 560;
const TW = MR - ML;

// Column x positions and widths
const C_DATE  = ML;
const C_DESC  = ML + 75;
const C_DEBIT = ML + 275;
const C_CRED  = ML + 350;
const C_BAL   = ML + 425;
const W_DATE  = 75;
const W_DESC  = 200;
const W_DEBIT = 75;
const W_CRED  = 75;
const W_BAL   = MR - C_BAL;

const ROW_H    = 18;
const HDR_H    = 20;
const TOP_RESERVE  = 130; // space for page header
const BOT_RESERVE  = 50;  // space for footer

export interface LedgerEntry {
  id: string;
  type: string;
  delta: number;
  balanceAfter: number;
  createdAt: Date | string;
  actorName?: string | null;
  companyName?: string | null;
  referenceType?: string | null;
}

export interface LedgerPdfOpts {
  retailerName: string;
  retailerGstin?: string | null;
  currentBalance: number;
  generatedAt: Date;
  entries: LedgerEntry[];
}

export function drawLedgerHeader(doc: PDoc, opts: LedgerPdfOpts, y: number): number {
  // Banner
  const BW = 180; const BH = 18; const BX = (PW - BW) / 2;
  doc.rect(BX, y, BW, BH).fillAndStroke('#000000', '#000000');
  doc.fillColor('#ffffff').fontSize(8.5).font('Helvetica-Bold')
    .text('PAYMENT LEDGER', BX, y + 5, { width: BW, align: 'center' });
  doc.fillColor('#000000');
  y += BH + 8;

  // Retailer name
  doc.fontSize(13).font('Helvetica-Bold')
    .text(opts.retailerName.toUpperCase(), ML, y, { width: TW, align: 'center' });
  y += 17;

  if (opts.retailerGstin) {
    doc.fontSize(8).font('Helvetica')
      .text(`GSTIN: ${opts.retailerGstin}`, ML, y, { width: TW, align: 'center' });
    y += 13;
  }

  // Generated date + outstanding balance
  doc.fontSize(8).font('Helvetica')
    .text(`Generated: ${fmtDate(opts.generatedAt)}`, ML, y)
    .font('Helvetica-Bold')
    .text(
      `Outstanding Balance: Rs. ${fmtAmt(opts.currentBalance)}`,
      ML, y, { width: TW, align: 'right' },
    );
  y += 14;

  doc.moveTo(ML, y).lineTo(MR, y).lineWidth(1).stroke();
  y += 8;

  return y;
}

function drawTableHeader(doc: PDoc, y: number): number {
  doc.rect(ML, y, TW, HDR_H).fill('#000000');
  const hY = y + (HDR_H - 8) / 2;
  doc.fillColor('#ffffff').fontSize(8).font('Helvetica-Bold')
    .text('DATE',        C_DATE  + 3, hY, { width: W_DATE  - 4 })
    .text('DESCRIPTION', C_DESC  + 3, hY, { width: W_DESC  - 4 })
    .text('DEBIT',       C_DEBIT + 2, hY, { width: W_DEBIT - 4, align: 'right' })
    .text('CREDIT',      C_CRED  + 2, hY, { width: W_CRED  - 4, align: 'right' })
    .text('BALANCE',     C_BAL   + 2, hY, { width: W_BAL   - 4, align: 'right' });
  doc.fillColor('#000000');
  return y + HDR_H;
}

export function generateLedgerPdf(opts: LedgerPdfOpts): Promise<Buffer> {
  const doc = new PDFDocument({ size: 'A4', margin: 15, autoFirstPage: false });
  const chunks: Buffer[] = [];
  doc.on('data', (c: Buffer) => chunks.push(c));

  const rowsPerPage = Math.floor((PH - TOP_RESERVE - BOT_RESERVE - HDR_H) / ROW_H);

  let entriesLeft = [...opts.entries];
  let isFirstPage = true;

  while (isFirstPage || entriesLeft.length > 0) {
    doc.addPage();
    let y = 28;

    y = drawLedgerHeader(doc, opts, y);
    y = drawTableHeader(doc, y);

    const pageStart = y;
    const batch = entriesLeft.splice(0, rowsPerPage);

    // Column separators
    [C_DESC, C_DEBIT, C_CRED, C_BAL].forEach(x => {
      doc.moveTo(x, pageStart).lineTo(x, pageStart + batch.length * ROW_H)
        .lineWidth(0.4).strokeColor('#cccccc').stroke().lineWidth(1).strokeColor('#000000');
    });

    for (let i = 0; i < batch.length; i++) {
      const e = batch[i];
      const ry = pageStart + i * ROW_H;
      const ty = ry + (ROW_H - 8) / 2;
      const delta = Number(e.delta);
      const bal   = Number(e.balanceAfter);
      const isDebit = delta > 0;

      if (i % 2 === 1) {
        doc.rect(ML, ry, TW, ROW_H).fill('#f9f9f9').fillColor('#000000');
      }

      const label = entryLabel(e.type, delta);
      const sub = e.companyName ?? e.actorName ?? null;

      doc.fontSize(8).font('Helvetica')
        .fillColor('#000000')
        .text(fmtDate(e.createdAt), C_DATE + 3, ty, { width: W_DATE - 4 })
        .text(sub ? `${label}\n${sub}` : label, C_DESC + 3, ty - (sub ? 3 : 0), { width: W_DESC - 4, lineBreak: false });

      if (isDebit) {
        doc.fillColor('#cc0000').font('Helvetica-Bold')
          .text(`Rs. ${fmtAmt(Math.abs(delta))}`, C_DEBIT + 2, ty, { width: W_DEBIT - 4, align: 'right' });
        doc.fillColor('#000000').font('Helvetica')
          .text('—', C_CRED + 2, ty, { width: W_CRED - 4, align: 'right' });
      } else {
        doc.fillColor('#000000').font('Helvetica')
          .text('—', C_DEBIT + 2, ty, { width: W_DEBIT - 4, align: 'right' });
        doc.fillColor('#007700').font('Helvetica-Bold')
          .text(`Rs. ${fmtAmt(Math.abs(delta))}`, C_CRED + 2, ty, { width: W_CRED - 4, align: 'right' });
      }

      const balColor = bal > 0 ? '#cc0000' : '#007700';
      doc.fillColor(balColor).font('Helvetica-Bold')
        .text(`Rs. ${fmtAmt(bal)}`, C_BAL + 2, ty, { width: W_BAL - 4, align: 'right' });

      doc.fillColor('#000000');

      // Row bottom border
      doc.moveTo(ML, ry + ROW_H).lineTo(MR, ry + ROW_H)
        .lineWidth(0.3).strokeColor('#dddddd').stroke()
        .lineWidth(1).strokeColor('#000000');
    }

    // Outer border
    const tableH = batch.length * ROW_H;
    doc.rect(ML, pageStart, TW, tableH).lineWidth(0.8).stroke();

    // Footer
    const footerY = PH - 35;
    doc.moveTo(ML, footerY).lineTo(MR, footerY).lineWidth(0.5).stroke();
    doc.fontSize(7.5).font('Helvetica').fillColor('#555555')
      .text(`${opts.retailerName} — Payment Ledger`, ML, footerY + 6)
      .text(`Page ${doc.bufferedPageRange().start + doc.bufferedPageRange().count}`, ML, footerY + 6, { width: TW, align: 'right' });
    doc.fillColor('#000000');

    isFirstPage = false;
    if (entriesLeft.length === 0) break;
  }

  return new Promise((resolve, reject) => {
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);
    doc.end();
  });
}
