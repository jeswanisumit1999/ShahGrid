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

interface ImportRow {
  name: string;
  phone: string;
  address: string;
  gstin: string;
  creditLimit: number;
  debit: number;
  credit: number;
  salesOfficerEmail: string;
}
export interface ImportResult { created: number; skipped: number; errors: string[]; }

function parseImportBuffer(buffer: Buffer): ImportRow[] {
  const wb = XLSX.read(buffer, { type: 'buffer' });
  const ws = wb.Sheets[wb.SheetNames[0]];
  const rows: unknown[][] = XLSX.utils.sheet_to_json(ws, { header: 1, defval: '' });

  // Row 1: Name | Phone Number | Address | GSTIN | Credit Limit | "Existing Pending Amount" (merged) | Sale Officer
  // Row 2: (empty cols) | Debit | Credit | (empty)
  // Row 3+: data
  const headerIdx = rows.findIndex(r =>
    r.map(c => String(c).trim().toLowerCase()).includes('name')
  );
  if (headerIdx === -1) throw AppError.badRequest('No "Name" header found in the file.');

  const col = (arr: string[], keyword: string) => arr.findIndex(c => c.includes(keyword));

  const hdr = rows[headerIdx].map(c => String(c).trim().toLowerCase());
  const nameCol         = col(hdr, 'name');
  const phoneCol        = col(hdr, 'phone');
  const addressCol      = col(hdr, 'address');
  const gstinCol        = col(hdr, 'gstin');
  const creditLimitCol  = col(hdr, 'credit limit');
  const salesOfficerCol = col(hdr, 'sale officer') !== -1 ? col(hdr, 'sale officer') : col(hdr, 'sales officer');

  // Debit/Credit are sub-headers in the row immediately after (under merged "Existing Pending Amount")
  const subHdr   = (rows[headerIdx + 1] ?? []).map(c => String(c).trim().toLowerCase());
  const debitCol  = col(subHdr, 'debit');
  const creditCol = col(subHdr, 'credit');

  if (debitCol === -1) throw AppError.badRequest('No "Debit" sub-header found in the file.');

  const result: ImportRow[] = [];
  for (let i = headerIdx + 2; i < rows.length; i++) {
    const row  = rows[i];
    const name = String(row[nameCol] ?? '').trim();
    if (!name) continue;
    result.push({
      name,
      phone:             String(row[phoneCol] ?? '').trim(),
      address:           String(row[addressCol] ?? '').trim(),
      gstin:             String(row[gstinCol] ?? '').trim(),
      creditLimit:       toNum(creditLimitCol !== -1 ? row[creditLimitCol] : 0),
      debit:             toNum(row[debitCol]),
      credit:            creditCol !== -1 ? toNum(row[creditCol]) : 0,
      salesOfficerEmail: salesOfficerCol !== -1 ? String(row[salesOfficerCol] ?? '').trim() : '',
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

  // Pre-load sales officer email → id map
  const emailSet = [...new Set(rows.map(r => r.salesOfficerEmail).filter(Boolean))];
  const salesOfficerMap: Record<string, string> = {};
  if (emailSet.length > 0) {
    const users = await prisma.user.findMany({
      where: { email: { in: emailSet } },
      select: { id: true, email: true },
    });
    for (const u of users) { salesOfficerMap[u.email.toLowerCase()] = u.id; }
  }

  for (const row of rows) {
    try {
      const existing = await prisma.retailer.findFirst({
        where: { name: { equals: row.name, mode: 'insensitive' } },
        select: { id: true, isActive: true },
      });
      // Active retailer already exists — skip
      if (existing?.isActive) { skipped++; continue; }

      // Use real phone if provided; otherwise generate a placeholder
      let phone = row.phone;
      if (!phone) {
        for (let attempt = 0; attempt < 10; attempt++) {
          const candidate = `IMPORT-${String(counter++).padStart(4, '0')}`;
          const taken = await prisma.retailer.findUnique({ where: { phone: candidate }, select: { id: true } });
          if (!taken) { phone = candidate; break; }
        }
        if (!phone) { errors.push(`${row.name}: could not assign placeholder phone`); continue; }
      }

      // Debit → positive pendingCollection; Credit → negative pendingCollection
      const pending = row.debit > 0
        ? new Prisma.Decimal(row.debit.toFixed(2))
        : row.credit > 0
          ? new Prisma.Decimal((-row.credit).toFixed(2))
          : new Prisma.Decimal(0);

      await prisma.$transaction(async (tx) => {
        // Reactivate a soft-deleted retailer if one exists, otherwise create fresh
        const retailer = existing
          ? await tx.retailer.update({
              where: { id: existing.id },
              data: {
                isActive:         true,
                phone:            phone || undefined,
                address:          row.address || null,
                gstin:            row.gstin || null,
                creditLimit:      new Prisma.Decimal(row.creditLimit.toFixed(2)),
                pendingCollection: pending,
              },
            })
          : await tx.retailer.create({
              data: {
                name:             row.name,
                phone,
                address:          row.address || null,
                gstin:            row.gstin || null,
                creditLimit:      new Prisma.Decimal(row.creditLimit.toFixed(2)),
                pendingCollection: pending,
              },
            });

        if (row.debit > 0) {
          await tx.retailerLedger.create({
            data: {
              retailerId:    retailer.id,
              delta:         pending,
              balanceAfter:  pending,
              type:          'opening_balance',
              referenceType: 'import',
              notes:         `Opening balance — debit: ${row.debit.toFixed(2)}`,
            },
          });
        } else if (row.credit > 0) {
          await tx.retailerLedger.create({
            data: {
              retailerId:    retailer.id,
              delta:         pending,
              balanceAfter:  pending,
              type:          'opening_credit',
              referenceType: 'import',
              notes:         `Opening credit — credit: ${row.credit.toFixed(2)}`,
            },
          });
        }

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
