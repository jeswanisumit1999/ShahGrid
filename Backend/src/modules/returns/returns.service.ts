import { Prisma } from '@prisma/client';
import { prisma } from '../../lib/prisma';
import { AppError } from '../../errors/AppError';
import { buildPrismaPage, buildPaginationResult } from '../../utils/pagination';
import { writeAuditLog } from '../../utils/audit';

interface ReturnItemInput {
  orderItemId: string;
  quantity: number;
}

export async function createReturn(
  input: {
    orderId: string;
    retailerId: string;
    reason?: string;
    items: ReturnItemInput[];
  },
  actorId: string
) {
  return prisma.$transaction(async (tx) => {
    const order = await tx.order.findUnique({
      where: { id: input.orderId },
      include: { orderItems: { include: { product: true } } },
    });
    if (!order) throw AppError.notFound('Order');

    const retailer = await tx.retailer.findUnique({ where: { id: input.retailerId } });
    if (!retailer) throw AppError.notFound('Retailer');

    const orderItemMap = Object.fromEntries(order.orderItems.map((oi) => [oi.id, oi]));

    let returnValue = 0;

    // Validate return quantities and compute return value
    for (const item of input.items) {
      const orderItem = orderItemMap[item.orderItemId];
      if (!orderItem) {
        throw AppError.badRequest(`Order item ${item.orderItemId} does not belong to this order`);
      }
      const delivered = orderItem.deliveredQuantity ?? 0;
      if (item.quantity > delivered) {
        throw AppError.badRequest(
          `Cannot return ${item.quantity} of "${orderItem.product.name}" — only ${delivered} delivered`
        );
      }
      returnValue += item.quantity * Number(orderItem.unitPrice);
    }

    const returnRecord = await tx.return.create({
      data: {
        orderId: input.orderId,
        retailerId: input.retailerId,
        returnValue,
        reason: input.reason,
        returnItems: {
          create: input.items.map((item) => ({
            orderItemId: item.orderItemId,
            quantity: item.quantity,
          })),
        },
      },
      include: { returnItems: true },
    });

    // Restore stock for returned items
    for (const item of input.items) {
      const orderItem = orderItemMap[item.orderItemId];
      await tx.product.update({
        where: { id: orderItem.productId },
        data: { stockQuantity: { increment: item.quantity } },
      });

      // Reduce delivered quantity
      await tx.orderItem.update({
        where: { id: item.orderItemId },
        data: { deliveredQuantity: { decrement: item.quantity } },
      });
    }

    // Decrement pendingCollection by return value
    const newPending = Math.max(0, Number(retailer.pendingCollection) - returnValue);
    await tx.retailer.update({
      where: { id: input.retailerId },
      data: { pendingCollection: newPending },
    });

    await writeAuditLog(tx, {
      actorId,
      action: 'create_return',
      entityType: 'Return',
      entityId: returnRecord.id,
      diff: { returnValue, itemCount: input.items.length },
    });

    return returnRecord;
  });
}

export async function listReturns(params: {
  cursor?: string;
  limit: number;
  orderId?: string;
  retailerId?: string;
}) {
  const where: Prisma.ReturnWhereInput = {
    ...(params.orderId && { orderId: params.orderId }),
    ...(params.retailerId && { retailerId: params.retailerId }),
  };

  const returns = await prisma.return.findMany({
    where,
    orderBy: { createdAt: 'desc' },
    ...buildPrismaPage(params),
    include: {
      order: { select: { id: true } },
      retailer: { select: { id: true, name: true } },
      returnItems: { include: { orderItem: { include: { product: { select: { id: true, name: true } } } } } },
    },
  });

  return buildPaginationResult(returns, params.limit);
}
