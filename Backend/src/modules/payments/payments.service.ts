import { Prisma } from '@prisma/client';
import { prisma } from '../../lib/prisma';
import { AppError } from '../../errors/AppError';
import { buildPrismaPage, buildPaginationResult } from '../../utils/pagination';
import { writeAuditLog } from '../../utils/audit';

export async function recordPayment(
  input: {
    orderId?: string;
    retailerId: string;
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

export async function listPayments(params: {
  cursor?: string;
  limit: number;
  orderId?: string;
  retailerId?: string;
}) {
  const where: Prisma.PaymentWhereInput = {
    ...(params.orderId && { orderId: params.orderId }),
    ...(params.retailerId && { retailerId: params.retailerId }),
  };

  const payments = await prisma.payment.findMany({
    where,
    orderBy: { createdAt: 'desc' },
    ...buildPrismaPage(params),
    include: {
      order: { select: { id: true } },
      retailer: { select: { id: true, name: true } },
    },
  });

  return buildPaginationResult(payments, params.limit);
}
