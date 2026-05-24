import { PrismaClient } from '@prisma/client';

type Tx = Omit<PrismaClient, '$connect' | '$disconnect' | '$on' | '$transaction' | '$use' | '$extends'>;

interface LedgerParams {
  productId: string;
  delta: number;
  balanceAfter: number;
  type: string;
  referenceType?: string;
  referenceId?: string;
  notes?: string;
  actorId?: string;
}

export async function writeStockLedger(tx: Tx, params: LedgerParams) {
  await tx.stockLedger.create({ data: params });
}
