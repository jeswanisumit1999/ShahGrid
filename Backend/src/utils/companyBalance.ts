import { PrismaClient } from '@prisma/client';

type Tx = Omit<PrismaClient, '$connect' | '$disconnect' | '$on' | '$transaction' | '$use' | '$extends'>;

export async function adjustCompanyBalance(
  tx: Tx,
  retailerId: string,
  companyId: string,
  delta: number
) {
  const existing = await tx.retailerCompanyBalance.findUnique({
    where: { retailerId_companyId: { retailerId, companyId } },
    select: { pendingAmount: true },
  });
  const current = Number(existing?.pendingAmount ?? 0);
  const newAmount = Math.max(0, current + delta);
  await tx.retailerCompanyBalance.upsert({
    where: { retailerId_companyId: { retailerId, companyId } },
    create: { retailerId, companyId, pendingAmount: newAmount },
    update: { pendingAmount: newAmount },
  });
}
