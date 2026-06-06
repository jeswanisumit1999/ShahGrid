/**
 * Import opening balances from a Tally "Sundry Debtors – Group Summary" XLS export.
 *
 * Usage:
 *   npx ts-node scripts/import-debtors.ts <path-to-file.xls>
 *
 * What it does for each row:
 *   1. Creates the retailer if no retailer with that name exists.
 *   2. Inserts a RetailerLedger entry with type = 'opening_balance'.
 *   3. Sets retailer.pendingCollection = net debit balance (debit - credit).
 *
 * Phone numbers are auto-generated as IMPORT-NNNN and must be updated manually.
 * Rows whose name already exists in the DB are skipped (no duplicates).
 */

import * as path from 'path';
import * as XLSX from 'xlsx';
import { PrismaClient, Prisma } from '@prisma/client';

const prisma = new PrismaClient();

// ── Types ─────────────────────────────────────────────────────────────────────

interface DebtorRow {
  name: string;
  debit: number;   // retailer owes us
  credit: number;  // we owe retailer
  net: number;     // debit - credit  (positive = we should collect)
}

// ── XLS parsing ───────────────────────────────────────────────────────────────

function parseXls(filePath: string): DebtorRow[] {
  const wb = XLSX.readFile(filePath);
  const ws = wb.Sheets[wb.SheetNames[0]];
  const rows: unknown[][] = XLSX.utils.sheet_to_json(ws, { header: 1, defval: '' });

  // Find the header row that contains "Particulars"
  let headerRowIdx = -1;
  for (let i = 0; i < rows.length; i++) {
    const cells = rows[i].map(c => String(c).trim().toLowerCase());
    if (cells.some(c => c === 'particulars')) {
      headerRowIdx = i;
      break;
    }
  }

  if (headerRowIdx === -1) {
    throw new Error('Could not find a row containing "Particulars". Check the XLS file.');
  }

  // Identify which columns hold name / debit / credit
  const headerCells = rows[headerRowIdx].map(c => String(c).trim().toLowerCase());
  const nameCol  = headerCells.findIndex(c => c === 'particulars');
  const debitCol = headerCells.findIndex(c => c.includes('debit'));
  const creditCol= headerCells.findIndex(c => c.includes('credit'));

  if (nameCol === -1)  throw new Error('No "Particulars" column found.');
  if (debitCol === -1) throw new Error('No "Debit" column found.');

  const results: DebtorRow[] = [];

  for (let i = headerRowIdx + 1; i < rows.length; i++) {
    const row = rows[i];
    const rawName = String(row[nameCol] ?? '').trim();

    if (!rawName) continue;
    if (rawName.toLowerCase().startsWith('grand total')) break;

    const debit  = parseAmount(row[debitCol]);
    const credit = creditCol !== -1 ? parseAmount(row[creditCol]) : 0;

    // Skip rows that have no balance at all
    if (debit === 0 && credit === 0) continue;

    results.push({ name: rawName, debit, credit, net: debit - credit });
  }

  return results;
}

function parseAmount(v: unknown): number {
  if (v === null || v === undefined || v === '') return 0;
  const n = typeof v === 'number' ? v : parseFloat(String(v).replace(/,/g, ''));
  return isNaN(n) ? 0 : n;
}

// ── Database import ───────────────────────────────────────────────────────────

async function importRows(rows: DebtorRow[]): Promise<void> {
  let created = 0;
  let skipped = 0;
  let counter = 1;

  for (const row of rows) {
    // Check for existing retailer by name (case-insensitive)
    const existing = await prisma.retailer.findFirst({
      where: { name: { equals: row.name, mode: 'insensitive' } },
    });

    if (existing) {
      console.log(`  SKIP   "${row.name}" — retailer already exists`);
      skipped++;
      continue;
    }

    // Generate a placeholder phone that fits in 20 chars
    const placeholderPhone = `IMPORT-${String(counter).padStart(4, '0')}`;
    counter++;

    const netDecimal = new Prisma.Decimal(row.net.toFixed(2));

    await prisma.$transaction(async (tx) => {
      const retailer = await tx.retailer.create({
        data: {
          name:              row.name,
          phone:             placeholderPhone,
          pendingCollection: netDecimal.greaterThan(0) ? netDecimal : new Prisma.Decimal(0),
        },
      });

      if (row.net !== 0) {
        await tx.retailerLedger.create({
          data: {
            retailerId:    retailer.id,
            delta:         netDecimal,
            balanceAfter:  netDecimal,
            type:          'opening_balance',
            referenceType: 'import',
            notes:         `Opening balance imported from Tally — Debit: ${row.debit.toFixed(2)}, Credit: ${row.credit.toFixed(2)}`,
          },
        });
      }
    });

    const sign = row.net >= 0 ? '+' : '';
    console.log(`  CREATE "${row.name}" | net: ${sign}${row.net.toFixed(2)} | phone: ${placeholderPhone}`);
    created++;
  }

  console.log('');
  console.log(`Done. Created: ${created}  Skipped: ${skipped}  Total rows: ${rows.length}`);
  if (created > 0) {
    console.log('');
    console.log('NOTE: Imported retailers have placeholder phone numbers (IMPORT-XXXX).');
    console.log('      Update them with real phone numbers before going live.');
  }
}

// ── Entry point ───────────────────────────────────────────────────────────────

async function main() {
  const filePath = process.argv[2];
  if (!filePath) {
    console.error('Usage: npx ts-node scripts/import-debtors.ts <path-to-file.xls>');
    process.exit(1);
  }

  const resolved = path.resolve(filePath);
  console.log(`Parsing: ${resolved}`);

  const rows = parseXls(resolved);
  console.log(`Found ${rows.length} debtor rows.\n`);

  if (rows.length === 0) {
    console.log('Nothing to import.');
    return;
  }

  // Preview first 5 rows
  console.log('Preview (first 5):');
  rows.slice(0, 5).forEach(r =>
    console.log(`  "${r.name}" — debit: ${r.debit}, credit: ${r.credit}, net: ${r.net}`)
  );
  console.log('');

  await importRows(rows);
}

main()
  .catch(err => { console.error(err); process.exit(1); })
  .finally(() => prisma.$disconnect());
