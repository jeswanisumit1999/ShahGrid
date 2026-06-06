import { Prisma } from '@prisma/client';
import * as XLSX from 'xlsx';
import { prisma } from '../../lib/prisma';
import { AppError } from '../../errors/AppError';
import { buildPrismaPage, buildPaginationResult } from '../../utils/pagination';
import { writeAuditLog } from '../../utils/audit';
import { writeRetailerLedger } from '../../utils/retailerLedger';

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

// ── XLS Import ────────────────────────────────────────────────────────────────

interface ImportRow { name: string; debit: number; credit: number; net: number; }
export interface ImportResult { created: number; skipped: number; errors: string[]; }

function parseImportBuffer(buffer: Buffer): ImportRow[] {
  const wb = XLSX.read(buffer, { type: 'buffer' });
  const ws = wb.Sheets[wb.SheetNames[0]];
  const rows: unknown[][] = XLSX.utils.sheet_to_json(ws, { header: 1, defval: '' });

  const headerIdx = rows.findIndex(r =>
    r.map(c => String(c).trim().toLowerCase()).includes('particulars')
  );
  if (headerIdx === -1) throw AppError.badRequest('No "Particulars" header found in the file.');

  const hdr  = rows[headerIdx].map(c => String(c).trim().toLowerCase());
  const nameCol  = hdr.findIndex(c => c === 'particulars');
  const debitCol = hdr.findIndex(c => c.includes('debit'));
  const creditCol= hdr.findIndex(c => c.includes('credit'));
  if (debitCol === -1) throw AppError.badRequest('No "Debit" column found in the file.');

  const result: ImportRow[] = [];
  for (let i = headerIdx + 1; i < rows.length; i++) {
    const row  = rows[i];
    const name = String(row[nameCol] ?? '').trim();
    if (!name) continue;
    if (name.toLowerCase().startsWith('grand total')) break;
    const debit  = toNum(row[debitCol]);
    const credit = creditCol !== -1 ? toNum(row[creditCol]) : 0;
    if (debit === 0 && credit === 0) continue;
    result.push({ name, debit, credit, net: debit - credit });
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

  for (const row of rows) {
    try {
      const existing = await prisma.retailer.findFirst({
        where: { name: { equals: row.name, mode: 'insensitive' } },
        select: { id: true },
      });
      if (existing) { skipped++; continue; }

      // Generate unique placeholder phone — retry if collision
      let phone = '';
      for (let attempt = 0; attempt < 10; attempt++) {
        const candidate = `IMPORT-${String(counter++).padStart(4, '0')}`;
        const taken = await prisma.retailer.findUnique({ where: { phone: candidate }, select: { id: true } });
        if (!taken) { phone = candidate; break; }
      }
      if (!phone) { errors.push(`${row.name}: could not assign placeholder phone`); continue; }

      const net = new Prisma.Decimal(row.net.toFixed(2));
      await prisma.$transaction(async (tx) => {
        const retailer = await tx.retailer.create({
          data: {
            name: row.name,
            phone,
            pendingCollection: net.greaterThan(0) ? net : new Prisma.Decimal(0),
          },
        });
        if (row.net !== 0) {
          await tx.retailerLedger.create({
            data: {
              retailerId:    retailer.id,
              delta:         net,
              balanceAfter:  net,
              type:          'opening_balance',
              referenceType: 'import',
              notes: `Tally import — debit: ${row.debit.toFixed(2)}, credit: ${row.credit.toFixed(2)}`,
            },
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
