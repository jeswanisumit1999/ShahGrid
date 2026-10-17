import { Prisma } from '@prisma/client';
import * as XLSX from 'xlsx';
import { prisma } from '../../lib/prisma';
import { AppError } from '../../errors/AppError';
import { buildPrismaPage, buildPaginationResult } from '../../utils/pagination';
import { writeAuditLog } from '../../utils/audit';
import { writeRetailerLedger } from '../../utils/retailerLedger';
import { adjustCompanyBalance } from '../../utils/companyBalance';

export async function recordPayment(
  input: {
    orderId?: string;
    retailerId: string;
    companyId?: string;
    amount: number;
    paymentDate: string;
    method: string;
    referenceNo?: string;
    idempotencyKey?: string;
    notes?: string;
  },
  actorId: string
) {
  // Idempotency check before entering the transaction
  if (input.idempotencyKey) {
    const existing = await prisma.payment.findUnique({
      where: { idempotencyKey: input.idempotencyKey },
    });
    if (existing) {
      // Return the existing payment — not an error, just a duplicate submission
      return existing;
    }
  }

  return prisma.$transaction(async (tx) => {
    if (input.orderId) {
      const order = await tx.order.findUnique({ where: { id: input.orderId } });
      if (!order) throw AppError.notFound('Order');
    }

    const retailer = await tx.retailer.findUnique({ where: { id: input.retailerId } });
    if (!retailer) throw AppError.notFound('Retailer');

    const payment = await tx.payment.create({
      data: {
        orderId: input.orderId ?? null,
        retailerId: input.retailerId,
        companyId: input.companyId ?? null,
        amount: input.amount,
        paymentDate: new Date(input.paymentDate),
        method: input.method,
        referenceNo: input.referenceNo,
        idempotencyKey: input.idempotencyKey,
        notes: input.notes,
      },
    });

    // Decrement pendingCollection — but never below zero
    const newPending = Math.max(0, Number(retailer.pendingCollection) - input.amount);
    await tx.retailer.update({
      where: { id: input.retailerId },
      data: { pendingCollection: newPending },
    });

    await writeRetailerLedger(tx, {
      retailerId: input.retailerId,
      companyId: input.companyId,
      delta: -input.amount,
      balanceAfter: newPending,
      type: 'payment_credit',
      referenceType: 'Payment',
      referenceId: payment.id,
      actorId,
    });

    // Decrement per-company balance if company specified
    if (input.companyId) {
      await adjustCompanyBalance(tx, input.retailerId, input.companyId, -input.amount);
    }

    await writeAuditLog(tx, {
      actorId,
      action: 'record_payment',
      entityType: 'Payment',
      entityId: payment.id,
      diff: { amount: input.amount, method: input.method, ...(input.orderId && { orderId: input.orderId }) },
    });

    return payment;
  });
}

// ── Tally Bank Book Import ────────────────────────────────────────────────────

export interface PaymentImportResult {
  imported: number;
  skipped: number;
  errors: string[];
  companyName: string;
  details: string[];   // debug: one line per imported row
}

interface PaymentRow {
  date: string;       // ISO YYYY-MM-DD
  retailerName: string;
  vchNo: string;
  amount: number;
}

function parseTallyDate(raw: string): string {
  // Handles "01-Oct-26", "01-Oct-2026", "1-Oct-26" etc.
  if (!raw) return '';
  const months: Record<string, string> = {
    jan: '01', feb: '02', mar: '03', apr: '04', may: '05', jun: '06',
    jul: '07', aug: '08', sep: '09', oct: '10', nov: '11', dec: '12',
  };
  const m = raw.trim().match(/^(\d{1,2})-([A-Za-z]{3})-(\d{2,4})$/);
  if (!m) return '';
  const [, dd, mon, yy] = m;
  const month = months[mon.toLowerCase()];
  if (!month) return '';
  const year = yy.length === 2 ? `20${yy}` : yy;
  return `${year}-${month}-${dd.padStart(2, '0')}`;
}

function parsePaymentBuffer(buffer: Buffer): { companyName: string; rows: PaymentRow[] } {
  const wb = XLSX.read(buffer, { type: 'buffer' });
  const ws = wb.Sheets[wb.SheetNames[0]];
  const rows: unknown[][] = XLSX.utils.sheet_to_json(ws, { header: 1, defval: '' });

  // Row 0 col 0 holds the company name
  const companyName = String(rows[0]?.[0] ?? '').trim().toUpperCase();
  if (!companyName) throw AppError.badRequest('Could not read company name from row 1 of the file.');

  // Find header row: contains "Particulars" and "Debit"
  let headerIdx = -1;
  for (let i = 0; i < Math.min(rows.length, 15); i++) {
    const cells = (rows[i] ?? []).map(c => String(c).trim().toLowerCase());
    if (cells.some(c => c === 'particulars') && cells.some(c => c === 'debit')) {
      headerIdx = i;
      break;
    }
  }
  if (headerIdx === -1) throw AppError.badRequest('Could not find header row with "Particulars" and "Debit" columns.');

  // Use header row to derive column positions
  const hdr = (rows[headerIdx] ?? []).map(c => String(c).trim().toLowerCase());
  const particularsCol = hdr.findIndex(c => c === 'particulars');
  const vchTypeCol     = hdr.findIndex(c => c.includes('vch') && c.includes('type'));
  const vchNoCol       = hdr.findIndex(c => c.includes('vch') && (c.includes('no') || c.includes('#')));
  const debitCol       = hdr.findIndex(c => c === 'debit');

  if (particularsCol === -1 || debitCol === -1) {
    throw AppError.badRequest('Missing required columns: Particulars, Debit.');
  }

  const result: PaymentRow[] = [];

  for (let i = headerIdx + 1; i < rows.length; i++) {
    const row = rows[i] ?? [];

    // ── Find which column in THIS row has the vch type value ──────────────────
    // Tally files may have "Particulars" as a merged cell that splits into
    // [prefix col, name col] in data, shifting Vch Type left by 1.
    // So we check the header-derived position first, then adjacent columns.
    let resolvedVchTypeCol = vchTypeCol;
    if (vchTypeCol !== -1) {
      const atHeader = String(row[vchTypeCol] ?? '').trim().toLowerCase();
      if (atHeader !== 'receipt' && atHeader !== 'payment') {
        // Try one column to the left (merged-cell offset scenario)
        const atLeft = String(row[vchTypeCol - 1] ?? '').trim().toLowerCase();
        if (atLeft === 'receipt' || atLeft === 'payment') resolvedVchTypeCol = vchTypeCol - 1;
      }
    } else {
      // No header match — scan the row for receipt/payment
      for (let j = 0; j < row.length; j++) {
        const v = String(row[j] ?? '').trim().toLowerCase();
        if (v === 'receipt' || v === 'payment') { resolvedVchTypeCol = j; break; }
      }
    }

    const vchType = resolvedVchTypeCol !== -1
      ? String(row[resolvedVchTypeCol] ?? '').trim().toLowerCase()
      : '';

    // Only process Receipt entries (money received from retailer)
    if (vchType !== 'receipt') continue;

    // ── Extract party name ────────────────────────────────────────────────────
    // Two layouts seen in Tally exports:
    //   A) Combined:  particularsCol = "To Krishna Marble"
    //   B) Split:     particularsCol = "To",  particularsCol+1 = "Krishna Marble"
    let rawName = String(row[particularsCol] ?? '').trim();
    if (/^(to|by)$/i.test(rawName)) {
      // Split layout — name is in the next column
      rawName = String(row[particularsCol + 1] ?? '').trim();
    } else {
      rawName = rawName.replace(/^(to|by)\s+/i, '').trim();
    }
    if (!rawName) continue;

    // ── Debit column — adjust if vchType col shifted ──────────────────────────
    const colShift = vchTypeCol !== -1 ? resolvedVchTypeCol - vchTypeCol : 0;
    const resolvedDebitCol = debitCol + colShift;
    const resolvedVchNoCol = vchNoCol !== -1 ? vchNoCol + colShift : -1;

    const amount = toPayNum(row[resolvedDebitCol]);
    if (amount <= 0) continue;

    const rawDate = String(row[0] ?? '').trim();
    const date    = parseTallyDate(rawDate) || new Date().toISOString().slice(0, 10);
    const vchNo   = resolvedVchNoCol !== -1 ? String(row[resolvedVchNoCol] ?? '').trim() : '';

    result.push({ date, retailerName: rawName, vchNo, amount });
  }

  return { companyName, rows: result };
}

function toPayNum(v: unknown): number {
  if (v === null || v === undefined || v === '') return 0;
  const n = typeof v === 'number' ? v : parseFloat(String(v).replace(/,/g, ''));
  return isNaN(n) ? 0 : n;
}

export async function importPayments(
  buffer: Buffer,
  actorId: string,
): Promise<PaymentImportResult> {
  const { companyName, rows } = parsePaymentBuffer(buffer);

  // Find company in DB
  const company = await prisma.company.findFirst({
    where: { name: { equals: companyName, mode: 'insensitive' }, isActive: true },
    select: { id: true, name: true },
  });
  if (!company) {
    throw AppError.badRequest(`Company "${companyName}" not found in the system. Please create it first.`);
  }

  let imported = 0, skipped = 0;
  const errors: string[] = [];
  const details: string[] = [];

  for (const row of rows) {
    try {
      // Try exact match first, then substring match
      let retailer = await prisma.retailer.findFirst({
        where: { name: { equals: row.retailerName, mode: 'insensitive' }, isActive: true },
        select: { id: true, name: true, pendingCollection: true },
      });
      if (!retailer) {
        retailer = await prisma.retailer.findFirst({
          where: { name: { contains: row.retailerName, mode: 'insensitive' }, isActive: true },
          select: { id: true, name: true, pendingCollection: true },
        });
      }

      if (!retailer) {
        errors.push(`Retailer not found: "${row.retailerName}" (Vch: ${row.vchNo || '-'})`);
        skipped++;
        continue;
      }

      const idempotencyKey = row.vchNo
        ? `tally-${company.id}-vch-${row.vchNo}`
        : `tally-${company.id}-${retailer.id}-${row.date}-${row.amount}`;

      const exists = await prisma.payment.findUnique({ where: { idempotencyKey } });
      if (exists) {
        details.push(`SKIP (already imported): "${retailer.name}" ₹${row.amount} Vch:${row.vchNo}`);
        skipped++;
        continue;
      }

      let paymentId = '';
      await prisma.$transaction(async (tx) => {
        const payment = await tx.payment.create({
          data: {
            retailerId:     retailer!.id,
            companyId:      company.id,
            amount:         row.amount,
            paymentDate:    new Date(row.date),
            method:         'bank_transfer',
            referenceNo:    row.vchNo || null,
            idempotencyKey,
            notes:          `Imported from Tally bank book — ${companyName}`,
          },
        });
        paymentId = payment.id;

        // Re-fetch pending inside transaction to avoid stale reads when multiple rows hit same retailer
        const fresh = await tx.retailer.findUnique({ where: { id: retailer!.id }, select: { pendingCollection: true } });
        const newPending = Math.max(0, Number(fresh?.pendingCollection ?? 0) - row.amount);

        await tx.retailer.update({ where: { id: retailer!.id }, data: { pendingCollection: newPending } });

        await writeRetailerLedger(tx, {
          retailerId:    retailer!.id,
          companyId:     company.id,
          delta:         -row.amount,
          balanceAfter:  newPending,
          type:          'payment_credit',
          referenceType: 'Payment',
          referenceId:   payment.id,
          actorId,
        });

        await adjustCompanyBalance(tx, retailer!.id, company.id, -row.amount);

        await writeAuditLog(tx, {
          actorId,
          action:     'import_payment',
          entityType: 'Payment',
          entityId:   payment.id,
          diff:       { amount: row.amount, retailerName: retailer!.name, vchNo: row.vchNo, date: row.date },
        });
      });

      details.push(`OK: "${retailer.name}" ₹${row.amount} ${row.date} Vch:${row.vchNo} id:${paymentId}`);
      imported++;
    } catch (err: any) {
      errors.push(`Error for "${row.retailerName}": ${err?.message ?? 'Unknown error'}`);
      skipped++;
    }
  }

  return { imported, skipped, errors, companyName: company.name, details };
}

export async function listPayments(params: {
  cursor?: string;
  limit: number;
  orderId?: string;
  retailerId?: string;
  search?: string;
}) {
  const where: Prisma.PaymentWhereInput = {
    ...(params.orderId && { orderId: params.orderId }),
    ...(params.retailerId && { retailerId: params.retailerId }),
    ...(params.search && {
      OR: [
        { retailer: { name: { contains: params.search, mode: 'insensitive' } } },
        { referenceNo: { contains: params.search, mode: 'insensitive' } },
      ],
    }),
  };

  const payments = await prisma.payment.findMany({
    where,
    orderBy: { createdAt: 'desc' },
    ...buildPrismaPage(params),
    include: {
      order: { select: { id: true } },
      retailer: { select: { id: true, name: true } },
      company: { select: { id: true, name: true } },
    },
  });

  return buildPaginationResult(payments, params.limit);
}
