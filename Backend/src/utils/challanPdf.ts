import PDFDocument from 'pdfkit';
import { PrismaClient } from '@prisma/client';

export type Tx = Omit<PrismaClient, '$connect' | '$disconnect' | '$on' | '$transaction' | '$use' | '$extends'>;
type PDoc = InstanceType<typeof PDFDocument>;

// ── Types ─────────────────────────────────────────────────────────────────────

export interface CompanyInfo {
  name: string;
  address: string | null;
  phone: string | null;
  gstin: string | null;
}

export interface ChallanOpts {
  challanNo: string;
  date: Date | string;
  company: CompanyInfo;
  recipientName: string;
  recipientGstin: string | null;
  items: { description: string; quantity: number; rate: number }[];
  notes: string | null;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function fmtDate(d: Date | string): string {
  const dt = new Date(d);
  const dd = String(dt.getDate()).padStart(2, '0');
  const mm = String(dt.getMonth() + 1).padStart(2, '0');
  const yy = String(dt.getFullYear()).slice(-2);
  return `${dd}/${mm}/${yy}`;
}

function fmtAmt(n: number): string {
  return n.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

// ── Layout constants (A5) ─────────────────────────────────────────────────────

const PW = 419;
const PH = 595;
const L  = 30;
const R  = 389;
const W  = R - L;

const C_DESC = L;
const C_QTY  = L + 200;
const C_RATE = C_QTY + 35;
const C_AMT  = C_RATE + 62;
const W_DESC = C_QTY - C_DESC;
const W_QTY  = C_RATE - C_QTY;
const W_RATE = C_AMT - C_RATE;
const W_AMT  = R - C_AMT;

const ROW_H = 20;
const HDR_H = 20;
const FOOTER_RESERVE = 60;

// ── Core drawing function ─────────────────────────────────────────────────────

export function drawChallan(doc: PDoc, opts: ChallanOpts): void {
  doc.addPage();
  let y = 28;

  // 1 ─ DELIVERY CHALLAN banner
  const BW = 150; const BH = 18; const BX = (PW - BW) / 2;
  doc.rect(BX, y, BW, BH).fillAndStroke('#000000', '#000000');
  doc.fillColor('#ffffff').fontSize(8).font('Helvetica-Bold')
    .text('DELIVERY CHALLAN', BX, y + 5, { width: BW, align: 'center' });
  doc.fillColor('#000000');
  y += BH + 8;

  // 2 ─ Company header
  doc.fontSize(14).font('Helvetica-Bold')
    .text(`M/S. ${opts.company.name.toUpperCase()}`, L, y, { width: W, align: 'center' });
  y += 18;
  if (opts.company.address) {
    doc.fontSize(7.5).font('Helvetica').text(opts.company.address, L, y, { width: W, align: 'center' });
    y += 11;
  }
  if (opts.company.phone) {
    doc.fontSize(7.5).font('Helvetica').text(`Mob.: ${opts.company.phone}`, L, y, { width: W, align: 'center' });
    y += 11;
  }
  if (opts.company.gstin) {
    doc.fontSize(8).font('Helvetica-Bold').text(`GSTIN NO.: ${opts.company.gstin}`, L, y, { width: W, align: 'center' });
    y += 11;
  }
  y += 8;

  // 3 ─ Challan No. | Date
  doc.fontSize(8).font('Helvetica').text('Challan No.', L, y);
  doc.font('Helvetica-Bold').text(opts.challanNo, L + 58, y);
  doc.font('Helvetica').text(`Date: ${fmtDate(opts.date)}`, L, y, { width: W, align: 'right' });
  y += 18;

  // 4 ─ Recipient name
  doc.fontSize(8).font('Helvetica').text('M/s.', L, y);
  doc.text(opts.recipientName, L + 26, y, { width: W - 26 });
  doc.moveTo(L + 26, y + 11).lineTo(R, y + 11).lineWidth(0.5).stroke().lineWidth(1);
  y += 18;

  // 5 ─ GSTIN line
  if (opts.recipientGstin) {
    const label = `GSTIN No.: ${opts.recipientGstin}`;
    const labelW = 140;
    const lx = (PW - labelW) / 2;
    doc.moveTo(L, y + 6).lineTo(lx - 6, y + 6).lineWidth(0.5).stroke().lineWidth(1);
    doc.fontSize(8).font('Helvetica-Bold').text(label, lx, y, { width: labelW, align: 'center' });
    doc.moveTo(lx + labelW + 6, y + 6).lineTo(R, y + 6).lineWidth(0.5).stroke().lineWidth(1);
  } else {
    doc.moveTo(L, y + 6).lineTo(R, y + 6).lineWidth(0.5).stroke().lineWidth(1);
  }
  y += 15;

  // 6 ─ Items table
  const tableTop = y;
  const availH = PH - FOOTER_RESERVE - tableTop;
  const dataRows = Math.max(1, Math.floor((availH - HDR_H) / ROW_H));
  const tableH = HDR_H + dataRows * ROW_H;

  doc.rect(L, tableTop, W, tableH).lineWidth(1).stroke();
  [C_QTY, C_RATE, C_AMT].forEach(x => {
    doc.moveTo(x, tableTop).lineTo(x, tableTop + tableH).lineWidth(1).stroke();
  });

  doc.rect(L + 0.5, tableTop + 0.5, W - 1, HDR_H - 1).fill('#ffffff').fillColor('#000000');
  const hY = tableTop + (HDR_H - 8) / 2;
  doc.fontSize(8).font('Helvetica-Bold')
    .text('DESCRIPTION', C_DESC + 5, hY, { width: W_DESC - 8 })
    .text('QTY.',   C_QTY + 2,  hY, { width: W_QTY - 4,  align: 'center' })
    .text('RATE',   C_RATE + 2, hY, { width: W_RATE - 4, align: 'center' })
    .text('AMOUNT', C_AMT + 2,  hY, { width: W_AMT - 4,  align: 'center' });
  doc.moveTo(L, tableTop + HDR_H).lineTo(R, tableTop + HDR_H).lineWidth(1).stroke();

  let total = 0;
  for (let i = 0; i < dataRows; i++) {
    const rowY = tableTop + HDR_H + i * ROW_H;
    if (i < dataRows - 1) {
      doc.moveTo(L, rowY + ROW_H).lineTo(R, rowY + ROW_H)
        .lineWidth(0.4).strokeColor('#000000').stroke()
        .lineWidth(1);
    }
    if (i < opts.items.length) {
      const it = opts.items[i];
      const amt = it.quantity * it.rate;
      total += amt;
      const tY = rowY + (ROW_H - 8) / 2;
      doc.fontSize(8.5).font('Helvetica')
        .text(it.description,      C_DESC + 5, tY, { width: W_DESC - 8 })
        .text(String(it.quantity),  C_QTY + 2,  tY, { width: W_QTY - 4,  align: 'center' })
        .text(fmtAmt(it.rate),     C_RATE + 2, tY, { width: W_RATE - 4, align: 'right' })
        .text(fmtAmt(amt),         C_AMT + 2,  tY, { width: W_AMT - 4,  align: 'right' });
    }
  }

  // Total line
  const totalY = tableTop + tableH + 6;
  doc.fontSize(8.5).font('Helvetica-Bold')
    .text(`Total: Rs. ${fmtAmt(total)}`, L, totalY, { width: W, align: 'right' });
  if (opts.notes) {
    doc.fontSize(7.5).font('Helvetica').text(`Notes: ${opts.notes}`, L, totalY + 13, { width: W });
  }

  // 7 ─ Footer
  const footerY = PH - 38;
  doc.moveTo(L, footerY).lineTo(R, footerY).lineWidth(0.8).stroke().lineWidth(1);
  const sigY = footerY + 7;
  doc.fontSize(8).font('Helvetica').text("Receiver's Sign.", L, sigY);
  doc.fontSize(8).font('Helvetica').text(`For M/S. ${opts.company.name.toUpperCase()}`, L, sigY, { width: W, align: 'right' });
}

// ── Challan number claim ──────────────────────────────────────────────────────

export async function claimChallanNumber(
  tx: Tx,
  entityType: 'order' | 'shipment' | 'direct_sale',
  entityId: string,
): Promise<string> {
  const setting = await tx.appSetting.findUnique({ where: { key: 'next_challan_number' } });
  const current = parseInt(setting?.value ?? '1', 10);
  await tx.appSetting.upsert({
    where: { key: 'next_challan_number' },
    create: { key: 'next_challan_number', value: String(current + 1), description: 'Next challan sequence number' },
    update: { value: String(current + 1) },
  });
  const num = String(current).padStart(4, '0');
  if (entityType === 'order') {
    await tx.order.update({ where: { id: entityId }, data: { challanNumber: num } });
  } else if (entityType === 'shipment') {
    await tx.shipment.update({ where: { id: entityId }, data: { challanNumber: num } });
  } else {
    await tx.directSale.update({ where: { id: entityId }, data: { challanNumber: num } });
  }
  return num;
}

// ── PDF document factory ──────────────────────────────────────────────────────

export function makePdfDoc(): { doc: PDoc; finish: () => Promise<Buffer> } {
  const doc = new PDFDocument({ size: 'A5', margin: 15, autoFirstPage: false });
  const chunks: Buffer[] = [];
  doc.on('data', (c: Buffer) => chunks.push(c));
  const finish = () => new Promise<Buffer>((resolve, reject) => {
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);
    doc.end();
  });
  return { doc, finish };
}
