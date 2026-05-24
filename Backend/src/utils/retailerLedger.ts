import { PrismaClient } from '@prisma/client';

type Tx = Omit<PrismaClient, '$connect' | '$disconnect' | '$on' | '$transaction' | '$use' | '$extends'>;

interface RetailerLedgerParams {
  retailerId: string;
  companyId?: string;
  delta: number;       // positive = debit (more owed), negative = credit (less owed)
  balanceAfter: number;
  type: string;
  referenceType?: string;
  referenceId?: string;
  notes?: string;
  actorId?: string;
}

export async function writeRetailerLedger(tx: Tx, params: RetailerLedgerParams) {
  await tx.retailerLedger.create({ data: params });
}
