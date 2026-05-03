import { Prisma } from '@prisma/client';
import { prisma } from '../../lib/prisma';
import { AppError } from '../../errors/AppError';
import { buildPrismaPage, buildPaginationResult } from '../../utils/pagination';
import { writeAuditLog } from '../../utils/audit';

interface OrderItemInput {
  productId: string;
  quantity: number;
  unitPrice: number;
}

export async function createOrder(
  input: {
    retailerId: string;
    salesOfficerId: string;
    isDirectSale?: boolean;
    overrideCompanyId?: string;
    notes?: string;
    items: OrderItemInput[];
  },
  actorId: string
) {
  return prisma.$transaction(async (tx) => {
    // ── 1. Load retailer ──────────────────────────────────────────────────────
    const retailer = await tx.retailer.findUnique({ where: { id: input.retailerId } });
    if (!retailer || !retailer.isActive) throw AppError.notFound('Retailer');

    // ── 2. Credit limit check ─────────────────────────────────────────────────
    const totalAmount = input.items.reduce(
      (sum, item) => sum + item.quantity * item.unitPrice,
      0
    );
    const creditCheckSetting = await tx.appSetting.findUnique({
      where: { key: 'allow_credit_override' },
    });
    const allowOverride = creditCheckSetting?.value === 'true';

    const projectedPending = Number(retailer.pendingCollection) + totalAmount;
    if (!allowOverride && projectedPending > Number(retailer.creditLimit)) {
      throw AppError.badRequest(
        `Order exceeds retailer credit limit. Limit: ${retailer.creditLimit}, current pending: ${retailer.pendingCollection}, order total: ${totalAmount}`,
        'CREDIT_LIMIT_EXCEEDED'
      );
    }

    // ── 3. Validate products exist ────────────────────────────────────────────
    const productIds = input.items.map((i) => i.productId);
    const products = await tx.product.findMany({
      where: { id: { in: productIds }, isActive: true },
    });
    if (products.length !== productIds.length) {
      throw AppError.notFound('One or more products');
    }
    const productMap = Object.fromEntries(products.map((p) => [p.id, p]));

    // ── 4. Create order + items ───────────────────────────────────────────────
    const order = await tx.order.create({
      data: {
        retailerId: input.retailerId,
        createdById: actorId,
        salesOfficerId: input.salesOfficerId,
        isDirectSale: input.isDirectSale ?? false,
        overrideCompanyId: input.overrideCompanyId ?? null,
        totalAmount,
        notes: input.notes,
        orderItems: {
          create: input.items.map((item) => ({
            productId: item.productId,
            quantity: item.quantity,
            unitPrice: item.unitPrice,
            deliveredQuantity: 0,
          })),
        },
      },
      include: { orderItems: true },
    });

    // ── 5. Direct-sale: deduct stock immediately, no shipments ────────────────
    if (input.isDirectSale) {
      for (const item of order.orderItems) {
        const product = productMap[item.productId];
        const newStock = product.stockQuantity - item.quantity;
        if (newStock < 0) {
          throw AppError.badRequest(
            `Insufficient stock for product "${product.name}" (available: ${product.stockQuantity}, requested: ${item.quantity})`,
            'INSUFFICIENT_STOCK'
          );
        }
        await tx.product.update({
          where: { id: item.productId },
          data: { stockQuantity: newStock },
        });
        await tx.orderItem.update({
          where: { id: item.id },
          data: { deliveredQuantity: item.quantity },
        });
      }
    } else {
      // ── 6. Normal order: group by company, then split by stock availability ──
      //
      // Each unique company gets at most two shipments:
      //   • "Pending Stock Verification"  – items (or portions) that have stock
      //   • "Pending Stock Availability"  – items (or portions) with no/partial stock
      //
      // overrideCompanyId forces all items into one company bucket.

      type ShipmentLine = { orderItemId: string; quantity: number };
      const companyAvailable = new Map<string, ShipmentLine[]>();
      const companyPending   = new Map<string, ShipmentLine[]>();

      for (const item of order.orderItems) {
        const product = productMap[item.productId];
        const effectiveCompanyId = input.overrideCompanyId ?? product.companyId;

        const available = Math.min(product.stockQuantity, item.quantity);
        const pending   = item.quantity - available;

        if (available > 0) {
          if (!companyAvailable.has(effectiveCompanyId)) companyAvailable.set(effectiveCompanyId, []);
          companyAvailable.get(effectiveCompanyId)!.push({ orderItemId: item.id, quantity: available });
        }
        if (pending > 0) {
          if (!companyPending.has(effectiveCompanyId)) companyPending.set(effectiveCompanyId, []);
          companyPending.get(effectiveCompanyId)!.push({ orderItemId: item.id, quantity: pending });
        }
      }

      // Collect all company IDs that appear in either bucket
      const allCompanyIds = new Set([...companyAvailable.keys(), ...companyPending.keys()]);

      for (const companyId of allCompanyIds) {
        const availableItems = companyAvailable.get(companyId) ?? [];
        const pendingItems   = companyPending.get(companyId)   ?? [];

        if (availableItems.length > 0) {
          await tx.shipment.create({
            data: {
              orderId: order.id,
              companyId,
              status: 'Pending Stock Verification',
              shipmentItems: { create: availableItems },
            },
          });
        }

        if (pendingItems.length > 0) {
          await tx.shipment.create({
            data: {
              orderId: order.id,
              companyId,
              status: 'Pending Stock Availability',
              shipmentItems: { create: pendingItems },
            },
          });
        }
      }

    }

    // ── 7. Increment retailer pendingCollection ───────────────────────────────
    await tx.retailer.update({
      where: { id: input.retailerId },
      data: { pendingCollection: { increment: totalAmount } },
    });

    await writeAuditLog(tx, {
      actorId,
      action: 'create_order',
      entityType: 'Order',
      entityId: order.id,
      diff: { totalAmount, isDirectSale: input.isDirectSale ?? false, itemCount: input.items.length },
    });

    return order;
  });
}

export async function listOrders(params: {
  cursor?: string;
  limit: number;
  retailerId?: string;
  salesOfficerId?: string;
}) {
  const where: Prisma.OrderWhereInput = {
    ...(params.retailerId && { retailerId: params.retailerId }),
    ...(params.salesOfficerId && { salesOfficerId: params.salesOfficerId }),
  };

  const orders = await prisma.order.findMany({
    where,
    orderBy: { createdAt: 'desc' },
    ...buildPrismaPage(params),
    include: {
      retailer: { select: { id: true, name: true } },
      salesOfficer: { select: { id: true, name: true } },
      orderItems: { include: { product: true } },
      shipments: { select: { id: true, status: true } },
    },
  });

  return buildPaginationResult(orders, params.limit);
}

export async function getOrderById(id: string) {
  const order = await prisma.order.findUnique({
    where: { id },
    include: {
      retailer: true,
      createdBy: { select: { id: true, name: true, email: true } },
      salesOfficer: { select: { id: true, name: true } },
      orderItems: {
        include: {
          product: { include: { company: true } },
          shipmentItems: { include: { shipment: true } },
        },
      },
      shipments: { include: { shipmentItems: true } },
      payments: true,
    },
  });
  if (!order) throw AppError.notFound('Order');
  return order;
}
