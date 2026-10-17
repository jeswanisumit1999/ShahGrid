import { Prisma } from '@prisma/client';
import * as XLSX from 'xlsx';
import { prisma } from '../../lib/prisma';
import { AppError } from '../../errors/AppError';
import { buildPrismaPage, buildPaginationResult } from '../../utils/pagination';
import { writeAuditLog } from '../../utils/audit';
import { writeRetailerLedger } from '../../utils/retailerLedger';
import { generateLedgerPdf } from '../../utils/ledgerPdf';

export async function listRetailers(params: {
  cursor?: string;
  limit: number;
  search?: string;
  salesOfficerId?: string;
  viewAll: boolean;
  requestingUserId: string;
}) {
  const where: Prisma.RetailerWhereInput = {
    isActive: true,
    ...(params.search && {
      OR: [
        { name: { contains: params.search, mode: 'insensitive' } },
        { phone: { contains: params.search } },
      ],
    }),
    // If the user can't view all retailers, filter to their assignments
    ...(!params.viewAll && {
      salesOfficers: { some: { salesOfficerId: params.requestingUserId } },
    }),
    ...(params.salesOfficerId && {
      salesOfficers: { some: { salesOfficerId: params.salesOfficerId } },
    }),
  };

  const retailers = await prisma.retailer.findMany({
    where,
    orderBy: { createdAt: 'asc' },
    ...buildPrismaPage(params),
    include: {
      companyBalances: {
        include: { company: { select: { id: true, name: true } } },
      },
    },
  });

  return buildPaginationResult(retailers, params.limit);
}

export async function getRetailerById(id: string) {
  const retailer = await prisma.retailer.findUnique({
    where: { id },
    include: {
      salesOfficers: { include: { salesOfficer: { select: { id: true, name: true, email: true } } } },
      companyBalances: {
        include: { company: { select: { id: true, name: true } } },
      },
    },
  });
  if (!retailer) throw AppError.notFound('Retailer');
  return retailer;
}

export async function createRetailer(
  data: {
    name: string;
    phone: string;
    address?: string;
    gstin?: string;
    creditLimit: number;
    initialPendingAmount?: number;
    isDirectSale: boolean;
    salesOfficerIds?: string[];
  },
  actorId: string
) {
  return prisma.$transaction(async (tx) => {
    const opening = data.initialPendingAmount ?? 0;

    const retailer = await tx.retailer.create({
      data: {
        name: data.name,
        phone: data.phone,
        address: data.address,
        gstin: data.gstin,
        creditLimit: data.creditLimit,
        pendingCollection: opening,
        isDirectSale: data.isDirectSale,
      },
    });

    if (opening > 0) {
      await writeRetailerLedger(tx, {
        retailerId: retailer.id,
        delta: opening,
        balanceAfter: opening,
        type: 'opening_balance',
        notes: 'Opening balance set during retailer migration',
        actorId,
      });
    }

    if (data.salesOfficerIds?.length) {
      await tx.retailerSalesOfficer.createMany({
        data: data.salesOfficerIds.map((id) => ({
          retailerId: retailer.id,
          salesOfficerId: id,
        })),
      });
    }

    await writeAuditLog(tx, {
      actorId,
      action: 'create_retailer',
      entityType: 'Retailer',
      entityId: retailer.id,
      diff: { ...data, initialPendingAmount: opening },
    });

    return retailer;
  });
}

export async function addManualPending(
  retailerId: string,
  amount: number,
  type: 'debit' | 'credit',
  notes: string | undefined,
  actorId: string
) {
  return prisma.$transaction(async (tx) => {
    const retailer = await tx.retailer.findUnique({ where: { id: retailerId } });
    if (!retailer) throw AppError.notFound('Retailer');

    const delta    = type === 'debit' ? amount : -amount;
    const newBal   = Number(retailer.pendingCollection) + delta;
    const deltaDec = new Prisma.Decimal(delta.toFixed(2));
    const balDec   = new Prisma.Decimal(newBal.toFixed(2));

    const updated = await tx.retailer.update({
      where: { id: retailerId },
      data:  { pendingCollection: balDec },
    });

    await tx.retailerLedger.create({
      data: {
        retailerId,
        delta:         deltaDec,
        balanceAfter:  balDec,
        type:          type === 'debit' ? 'manual_debit' : 'manual_credit',
        referenceType: 'manual',
        notes:         notes || null,
        actorId,
      },
    });

    await writeAuditLog(tx, {
      actorId,
      action:     'manual_pending_adjustment',
      entityType: 'Retailer',
      entityId:   retailerId,
      diff:       { delta, newBalance: newBal, type, notes },
    });

    return updated;
  });
}

export async function deleteRetailer(id: string, actorId: string) {
  const retailer = await prisma.retailer.findUnique({ where: { id } });
  if (!retailer) throw AppError.notFound('Retailer');
  if (!retailer.isActive) throw AppError.conflict('Retailer is already deleted');

  return prisma.$transaction(async (tx) => {
    const deleted = await tx.retailer.update({ where: { id }, data: { isActive: false } });
    await writeAuditLog(tx, {
      actorId,
      action: 'delete_retailer',
      entityType: 'Retailer',
      entityId: id,
      diff: { isActive: false },
    });
    return deleted;
  });
}

export async function getRetailerLedger(retailerId: string, params: {
  cursor?: string;
  limit: number;
}) {
  const retailer = await prisma.retailer.findUnique({
    where: { id: retailerId },
    select: { id: true, name: true, pendingCollection: true },
  });
  if (!retailer) throw AppError.notFound('Retailer');

  const entries = await prisma.retailerLedger.findMany({
    where: { retailerId },
    orderBy: { createdAt: 'desc' },
    ...buildPrismaPage(params),
  });

  const result = buildPaginationResult(entries, params.limit);

  const actorIds = [...new Set(result.items.map((e) => e.actorId).filter(Boolean))] as string[];
  const actors = actorIds.length
    ? await prisma.user.findMany({ where: { id: { in: actorIds } }, select: { id: true, name: true } })
    : [];
  const actorMap = Object.fromEntries(actors.map((a) => [a.id, a.name]));

  const companyIds = [...new Set(result.items.map((e) => e.companyId).filter(Boolean))] as string[];
  const companies = companyIds.length
    ? await prisma.company.findMany({ where: { id: { in: companyIds } }, select: { id: true, name: true } })
    : [];
  const companyMap = Object.fromEntries(companies.map((c) => [c.id, c.name]));

  return {
    retailer,
    items: result.items.map((e) => ({
      ...e,
      actorName: e.actorId ? (actorMap[e.actorId] ?? null) : null,
      companyName: e.companyId ? (companyMap[e.companyId] ?? null) : null,
    })),
    hasMore: result.hasMore,
    nextCursor: result.nextCursor,
  };
}

export async function updateRetailer(
  id: string,
  data: Partial<{
    name: string;
    phone: string;
    address: string;
    gstin: string;
    creditLimit: number;
    isDirectSale: boolean;
    salesOfficerIds: string[];
  }>,
  actorId: string
) {
  const retailer = await prisma.retailer.findUnique({ where: { id } });
  if (!retailer) throw AppError.notFound('Retailer');

  return prisma.$transaction(async (tx) => {
    const { salesOfficerIds, ...fields } = data;

    const updated = await tx.retailer.update({ where: { id }, data: fields });

    if (salesOfficerIds !== undefined) {
      await tx.retailerSalesOfficer.deleteMany({ where: { retailerId: id } });
      if (salesOfficerIds.length) {
        await tx.retailerSalesOfficer.createMany({
          data: salesOfficerIds.map((soId) => ({
            retailerId: id,
            salesOfficerId: soId,
          })),
        });
      }
    }

    await writeAuditLog(tx, {
      actorId,
      action: 'update_retailer',
      entityType: 'Retailer',
      entityId: id,
      diff: data,
    });

    return updated;
  });
}

export async function generateRetailerLedgerPdf(retailerId: string): Promise<Buffer> {
  const retailer = await prisma.retailer.findUnique({
    where: { id: retailerId },
    select: { id: true, name: true, gstin: true, pendingCollection: true },
  });
  if (!retailer) throw AppError.notFound('Retailer');

  const entries = await prisma.retailerLedger.findMany({
    where: { retailerId },
    orderBy: { createdAt: 'asc' },
  });

  const actorIds = [...new Set(entries.map((e) => e.actorId).filter(Boolean))] as string[];
  const actors = actorIds.length
    ? await prisma.user.findMany({ where: { id: { in: actorIds } }, select: { id: true, name: true } })
    : [];
  const actorMap = Object.fromEntries(actors.map((a) => [a.id, a.name]));

  const companyIds = [...new Set(entries.map((e) => e.companyId).filter(Boolean))] as string[];
  const companies = companyIds.length
    ? await prisma.company.findMany({ where: { id: { in: companyIds } }, select: { id: true, name: true } })
    : [];
  const companyMap = Object.fromEntries(companies.map((c) => [c.id, c.name]));

  return generateLedgerPdf({
    retailerName: retailer.name,
    retailerGstin: retailer.gstin,
    currentBalance: Number(retailer.pendingCollection),
    generatedAt: new Date(),
    entries: entries.map((e) => ({
      id: e.id,
      type: e.type,
      delta: Number(e.delta),
      balanceAfter: Number(e.balanceAfter),
      createdAt: e.createdAt,
      actorName: e.actorId ? (actorMap[e.actorId] ?? null) : null,
      companyName: e.companyId ? (companyMap[e.companyId] ?? null) : null,
      referenceType: e.referenceType,
    })),
  });
}

// ── XLS Import ────────────────────────────────────────────────────────────────

interface CompanyAmount { companyName: string; debit: number; credit: number; }
interface ImportRow {
  name: string;
  phone: string;
  address: string;
  gstin: string;
  creditLimit: number;
  salesOfficerEmail: string;
  companyAmounts: CompanyAmount[]; // one entry per company column-pair in the sheet
}
export interface ImportResult { created: number; skipped: number; errors: string[]; }

function parseImportBuffer(buffer: Buffer): ImportRow[] {
  const wb = XLSX.read(buffer, { type: 'buffer' });
  const ws = wb.Sheets[wb.SheetNames[0]];
  const rows: unknown[][] = XLSX.utils.sheet_to_json(ws, { header: 1, defval: '' });

  // ── Locate structural rows ────────────────────────────────────────────────
  //
  // Supported layouts (both detected automatically):
  //
  //   Multi-company (new):
  //     Row 0  — company names in merged cells  (Shah Trading Co. | Delux Tiles …)
  //     Row 1  — base headers                   (Name | Phone | … | Existing Pending Amount | … | Sale Officer)
  //     Row 2  — debit/credit sub-headers        (Debit | Credit | Debit | Credit …)
  //     Row 3+ — data
  //
  //   Single-company (legacy):
  //     Row 0  — base headers                   (Name | Phone | … | Existing Pending Amount | Sale Officer)
  //     Row 1  — debit/credit sub-headers        (Debit | Credit)
  //     Row 2+ — data

  const headerIdx = rows.findIndex(r =>
    r.map(c => String(c).trim().toLowerCase()).includes('name')
  );
  if (headerIdx === -1) throw AppError.badRequest('No "Name" header found in the file.');

  const col = (arr: string[], keyword: string) => arr.findIndex(c => c.includes(keyword));

  // Base column positions (from headerIdx row)
  const hdr = rows[headerIdx].map(c => String(c).trim().toLowerCase());
  const nameCol         = col(hdr, 'name');
  const phoneCol        = col(hdr, 'phone');
  const addressCol      = col(hdr, 'address');
  const gstinCol        = col(hdr, 'gstin');
  const creditLimitCol  = col(hdr, 'credit limit');
  const salesOfficerCol = col(hdr, 'sale officer') !== -1 ? col(hdr, 'sale officer') : col(hdr, 'sales officer');

  // Search for the "Debit" sub-header in the rows immediately following headerIdx.
  // Handles layouts with 1 or 2 intermediate rows before the Debit/Credit row
  // (e.g. "Existing Pending Amount" label row between the main header and Debit/Credit).
  let subHdrIdx = -1;
  for (let i = headerIdx + 1; i <= Math.min(headerIdx + 5, rows.length - 1); i++) {
    const r = (rows[i] ?? []).map(c => String(c).trim().toLowerCase());
    if (r.some(c => c === 'debit')) { subHdrIdx = i; break; }
  }
  if (subHdrIdx === -1) throw AppError.badRequest('No "Debit" sub-header found in the file.');

  const subHdr = (rows[subHdrIdx] ?? []).map(c => String(c).trim().toLowerCase());

  // Collect all debit column indices; each one starts a company column-pair
  const debitCols: number[] = subHdr.reduce<number[]>((acc, cell, i) => {
    if (cell === 'debit') acc.push(i);
    return acc;
  }, []);

  // Company names: scan every row from headerIdx up to (not including) subHdrIdx.
  // The company name for a given debit column is the first non-standard, non-empty
  // value found at that column position across those rows.
  const skipKeywords = ['name', 'phone', 'address', 'gstin', 'credit', 'debit', 'sale',
                        'officer', 'existing', 'pending', 'amount', 'limit'];

  function findCompanyName(debitCol: number): string {
    for (let r = headerIdx; r < subHdrIdx; r++) {
      // Check the debit column and one column to the left (merged cells land on the first col)
      for (const c of [debitCol, debitCol - 1]) {
        const cell = String((rows[r] ?? [])[c] ?? '').trim();
        if (cell && !skipKeywords.some(k => cell.toLowerCase().includes(k))) return cell;
      }
    }
    return '';
  }

  // Build company-column map: for each debit col → { companyName, debitCol, creditCol }
  const companyCols = debitCols.map((debitCol) => {
    const creditCol  = subHdr.indexOf('credit', debitCol + 1); // next 'credit' after this debit
    const companyName = findCompanyName(debitCol);
    return { companyName, debitCol, creditCol };
  });

  // ── Parse data rows ───────────────────────────────────────────────────────
  const dataStart = subHdrIdx + 1;
  const result: ImportRow[] = [];

  for (let i = dataStart; i < rows.length; i++) {
    const row  = rows[i];
    const name = String(row[nameCol] ?? '').trim();
    if (!name) continue;

    const companyAmounts: CompanyAmount[] = companyCols
      .map(({ companyName, debitCol, creditCol }) => ({
        companyName,
        debit:  toNum(row[debitCol]),
        credit: creditCol !== -1 ? toNum(row[creditCol]) : 0,
      }))
      .filter(c => c.debit !== 0 || c.credit !== 0);

    result.push({
      name,
      phone:             String(row[phoneCol] ?? '').trim(),
      address:           String(row[addressCol] ?? '').trim(),
      gstin:             String(row[gstinCol] ?? '').trim(),
      creditLimit:       toNum(creditLimitCol !== -1 ? row[creditLimitCol] : 0),
      salesOfficerEmail: salesOfficerCol !== -1 ? String(row[salesOfficerCol] ?? '').trim() : '',
      companyAmounts,
    });
  }
  return result;
}

function toNum(v: unknown): number {
  if (v === null || v === undefined || v === '') return 0;
  const n = typeof v === 'number' ? v : parseFloat(String(v).replace(/,/g, ''));
  return isNaN(n) ? 0 : n;
}

export async function importRetailers(buffer: Buffer): Promise<ImportResult> {
  const rows = parseImportBuffer(buffer);
  let created = 0, skipped = 0;
  const errors: string[] = [];
  let counter = 1;

  // ── Pre-load / create companies ───────────────────────────────────────────
  const companyNames = [
    ...new Set(
      rows.flatMap(r => r.companyAmounts.map(c => c.companyName))
          .filter(Boolean)
          .map(n => n.trim().toUpperCase())   // normalize to uppercase
    ),
  ];
  const companyIdMap: Record<string, string> = {}; // upperName → id
  for (const name of companyNames) {
    let company = await prisma.company.findFirst({
      where: { name: { equals: name, mode: 'insensitive' } },
      select: { id: true },
    });
    if (!company) {
      company = await prisma.company.create({ data: { name }, select: { id: true } });
    }
    companyIdMap[name] = company.id;
  }

  // ── Pre-load sales officers ───────────────────────────────────────────────
  const emailSet = [...new Set(rows.map(r => r.salesOfficerEmail).filter(Boolean))];
  const salesOfficerMap: Record<string, string> = {};
  if (emailSet.length > 0) {
    const users = await prisma.user.findMany({
      where: { email: { in: emailSet } },
      select: { id: true, email: true },
    });
    for (const u of users) { salesOfficerMap[u.email.toLowerCase()] = u.id; }
  }

  // ── Process each row ──────────────────────────────────────────────────────
  for (const row of rows) {
    try {
      const existing = await prisma.retailer.findFirst({
        where: { name: { equals: row.name, mode: 'insensitive' } },
        select: { id: true, isActive: true },
      });
      if (existing?.isActive) { skipped++; continue; }

      // Normalise phone
      const phone = row.phone.replace(/\s+/g, '').replace(/[^\d+]/g, '')
        || `IMPORT-${String(counter++).padStart(4, '0')}`;

      // Total pendingCollection = sum of (debit − credit) across all companies
      const totalNet = row.companyAmounts.reduce((sum, c) => sum + c.debit - c.credit, 0);
      const totalPending = new Prisma.Decimal(totalNet.toFixed(2));

      await prisma.$transaction(async (tx) => {
        // Create or reactivate retailer
        const retailer = existing
          ? await tx.retailer.update({
              where: { id: existing.id },
              data: {
                isActive:          true,
                phone:             phone || undefined,
                address:           row.address || null,
                gstin:             row.gstin || null,
                creditLimit:       new Prisma.Decimal(row.creditLimit.toFixed(2)),
                pendingCollection: totalPending,
              },
            })
          : await tx.retailer.create({
              data: {
                name:              row.name,
                phone,
                address:           row.address || null,
                gstin:             row.gstin || null,
                creditLimit:       new Prisma.Decimal(row.creditLimit.toFixed(2)),
                pendingCollection: totalPending,
              },
            });

        // Per-company balance + ledger entries
        for (const ca of row.companyAmounts) {
          const companyId = ca.companyName ? companyIdMap[ca.companyName.trim().toUpperCase()] : undefined;
          const net = ca.debit - ca.credit;
          const companyNet = new Prisma.Decimal(net.toFixed(2));

          if (companyId) {
            await tx.retailerCompanyBalance.upsert({
              where: { retailerId_companyId: { retailerId: retailer.id, companyId } },
              create: { retailerId: retailer.id, companyId, pendingAmount: companyNet },
              update: { pendingAmount: companyNet },
            });
          }

          const ledgerDelta = ca.debit > 0
            ? new Prisma.Decimal(ca.debit.toFixed(2))
            : new Prisma.Decimal((-ca.credit).toFixed(2));

          await tx.retailerLedger.create({
            data: {
              retailerId:    retailer.id,
              companyId:     companyId ?? null,
              delta:         ledgerDelta,
              balanceAfter:  companyNet,
              type:          ca.debit > 0 ? 'opening_balance' : 'opening_credit',
              referenceType: 'import',
              notes: ca.companyName
                ? `${ca.companyName} — ${ca.debit > 0 ? `debit: ${ca.debit.toFixed(2)}` : `credit: ${ca.credit.toFixed(2)}`}`
                : `Import — ${ca.debit > 0 ? `debit: ${ca.debit.toFixed(2)}` : `credit: ${ca.credit.toFixed(2)}`}`,
            },
          });
        }

        // Sales officer assignment
        const officerId = row.salesOfficerEmail
          ? salesOfficerMap[row.salesOfficerEmail.toLowerCase()]
          : undefined;
        if (officerId) {
          await tx.retailerSalesOfficer.upsert({
            where: { retailerId_salesOfficerId: { retailerId: retailer.id, salesOfficerId: officerId } },
            create: { retailerId: retailer.id, salesOfficerId: officerId },
            update: {},
          });
        }
      });
      created++;
    } catch (err: any) {
      errors.push(`${row.name}: ${err?.message ?? 'unknown error'}`);
    }
  }
  return { created, skipped, errors };
}
