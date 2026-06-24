import { PrismaClient } from '@prisma/client';
import { prisma } from '../../lib/prisma';

type Tx = Omit<PrismaClient, '$connect' | '$disconnect' | '$on' | '$transaction' | '$use' | '$extends'>;
import { AppError } from '../../errors/AppError';
import { buildPrismaPage, buildPaginationResult } from '../../utils/pagination';
import { writeAuditLog } from '../../utils/audit';
import { writeStockLedger } from '../../utils/stockLedger';
import { writeRetailerLedger } from '../../utils/retailerLedger';
import { adjustCompanyBalance } from '../../utils/companyBalance';

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
    paidAmount?: number;
    overrideCompanyId?: string;
    notes?: string;
    items: OrderItemInput[];
  },
  actorId: string
) {
  return prisma.$transaction(async (tx: Tx) => {
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

    if (input.paidAmount != null && input.paidAmount > totalAmount) {
      throw AppError.badRequest(
        `Paid amount (${input.paidAmount}) cannot exceed order total (${totalAmount})`,
        'PAID_AMOUNT_EXCEEDS_TOTAL'
      );
    }

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
    const productMap = Object.fromEntries(products.map((p: (typeof products)[0]) => [p.id, p]));

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
        await writeStockLedger(tx, {
          productId: item.productId,
          delta: -item.quantity,
          balanceAfter: newStock,
          type: 'direct_sale_out',
          referenceType: 'Order',
          referenceId: order.id,
          actorId,
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

    // ── 7. Increment retailer pendingCollection + per-company balances ────────
    const afterOrderDebit = await tx.retailer.update({
      where: { id: input.retailerId },
      data: { pendingCollection: { increment: totalAmount } },
    });
    await writeRetailerLedger(tx, {
      retailerId: input.retailerId,
      companyId: input.overrideCompanyId,
      delta: totalAmount,
      balanceAfter: Number(afterOrderDebit.pendingCollection),
      type: 'order_debit',
      referenceType: 'Order',
      referenceId: order.id,
      actorId,
    });

    // Compute per-company subtotals from the created order items
    const companyTotals = new Map<string, number>();
    for (const item of order.orderItems) {
      const product = productMap[item.productId];
      const cid = input.overrideCompanyId ?? product.companyId;
      companyTotals.set(cid, (companyTotals.get(cid) ?? 0) + item.quantity * Number(item.unitPrice));
    }
    for (const [cid, amount] of companyTotals) {
      await adjustCompanyBalance(tx, input.retailerId, cid, amount);
    }

    // ── 8. Direct-sale payment: record and reduce pendingCollection ───────────
    let paidAmount = 0;
    if (input.isDirectSale && input.paidAmount != null && input.paidAmount > 0) {
      paidAmount = Math.min(input.paidAmount, totalAmount);
      const payment = await tx.payment.create({
        data: {
          orderId: order.id,
          retailerId: input.retailerId,
          amount: paidAmount,
          paymentDate: new Date(),
          method: 'cash',
        },
      });
      const afterDirectPayment = await tx.retailer.update({
        where: { id: input.retailerId },
        data: { pendingCollection: { decrement: paidAmount } },
      });
      await writeRetailerLedger(tx, {
        retailerId: input.retailerId,
        delta: -paidAmount,
        balanceAfter: Number(afterDirectPayment.pendingCollection),
        type: 'payment_credit',
        referenceType: 'Order',
        referenceId: order.id,
        actorId,
      });
      // Distribute payment proportionally across company balances
      if (totalAmount > 0) {
        for (const [cid, companyAmount] of companyTotals) {
          const companyPayment = (companyAmount / totalAmount) * paidAmount;
          if (companyPayment > 0) await adjustCompanyBalance(tx, input.retailerId, cid, -companyPayment);
        }
      }
      await writeAuditLog(tx, {
        actorId,
        action: 'record_payment',
        entityType: 'Payment',
        entityId: payment.id,
        diff: { amount: paidAmount, method: 'cash', orderId: order.id, source: 'direct_sale' },
      });
    }

    await writeAuditLog(tx, {
      actorId,
      action: 'create_order',
      entityType: 'Order',
      entityId: order.id,
      diff: { totalAmount, isDirectSale: input.isDirectSale ?? false, paidAmount, itemCount: input.items.length },
    });

    return order;
  });
}

export async function addOrderItem(
  orderId: string,
  input: { productId: string; quantity: number; unitPrice: number },
  actorId: string
) {
  return prisma.$transaction(async (tx: Tx) => {
    const order = await tx.order.findUnique({
      where: { id: orderId },
      include: { retailer: true },
    });
    if (!order) throw AppError.notFound('Order');

    const product = await tx.product.findUnique({ where: { id: input.productId } });
    if (!product || !product.isActive) throw AppError.notFound('Product');

    const itemTotal = input.quantity * input.unitPrice;

    const creditCheckSetting = await tx.appSetting.findUnique({ where: { key: 'allow_credit_override' } });
    const allowOverride = creditCheckSetting?.value === 'true';
    const projectedPending = Number(order.retailer.pendingCollection) + itemTotal;
    if (!allowOverride && projectedPending > Number(order.retailer.creditLimit)) {
      throw AppError.badRequest(
        `Adding this item exceeds the retailer's credit limit. Limit: ${order.retailer.creditLimit}, current pending: ${order.retailer.pendingCollection}, adding: ${itemTotal}`,
        'CREDIT_LIMIT_EXCEEDED'
      );
    }

    const orderItem = await tx.orderItem.create({
      data: {
        orderId,
        productId: input.productId,
        quantity: input.quantity,
        unitPrice: input.unitPrice,
        deliveredQuantity: 0,
      },
    });

    await tx.order.update({ where: { id: orderId }, data: { totalAmount: { increment: itemTotal } } });
    const effectiveCompanyId = order.overrideCompanyId ?? product.companyId;
    const afterItemAdded = await tx.retailer.update({
      where: { id: order.retailerId },
      data: { pendingCollection: { increment: itemTotal } },
    });
    await writeRetailerLedger(tx, {
      retailerId: order.retailerId,
      companyId: effectiveCompanyId,
      delta: itemTotal,
      balanceAfter: Number(afterItemAdded.pendingCollection),
      type: 'item_added',
      referenceType: 'Order',
      referenceId: orderId,
      actorId,
    });
    await adjustCompanyBalance(tx, order.retailerId, effectiveCompanyId, itemTotal);

    if (order.isDirectSale) {
      const newStock = product.stockQuantity - input.quantity;
      if (newStock < 0) {
        throw AppError.badRequest(
          `Insufficient stock for "${product.name}" (available: ${product.stockQuantity}, requested: ${input.quantity})`,
          'INSUFFICIENT_STOCK'
        );
      }
      await tx.product.update({ where: { id: product.id }, data: { stockQuantity: newStock } });
      await writeStockLedger(tx, {
        productId: product.id,
        delta: -input.quantity,
        balanceAfter: newStock,
        type: 'direct_sale_out',
        referenceType: 'Order',
        referenceId: orderId,
        actorId,
      });
      await tx.orderItem.update({ where: { id: orderItem.id }, data: { deliveredQuantity: input.quantity } });
    } else {
      const available = Math.min(product.stockQuantity, input.quantity);
      const pending = input.quantity - available;

      if (available > 0) {
        const existingShipment = await tx.shipment.findFirst({
          where: { orderId, companyId: effectiveCompanyId, status: 'Pending Stock Verification' },
        });
        if (existingShipment) {
          await tx.shipmentItem.create({
            data: { shipmentId: existingShipment.id, orderItemId: orderItem.id, quantity: available },
          });
        } else {
          await tx.shipment.create({
            data: {
              orderId,
              companyId: effectiveCompanyId,
              status: 'Pending Stock Verification',
              shipmentItems: { create: [{ orderItemId: orderItem.id, quantity: available }] },
            },
          });
        }
      }

      if (pending > 0) {
        const existingShipment = await tx.shipment.findFirst({
          where: { orderId, companyId: effectiveCompanyId, status: 'Pending Stock Availability' },
        });
        if (existingShipment) {
          await tx.shipmentItem.create({
            data: { shipmentId: existingShipment.id, orderItemId: orderItem.id, quantity: pending },
          });
        } else {
          await tx.shipment.create({
            data: {
              orderId,
              companyId: effectiveCompanyId,
              status: 'Pending Stock Availability',
              shipmentItems: { create: [{ orderItemId: orderItem.id, quantity: pending }] },
            },
          });
        }
      }
    }

    await writeAuditLog(tx, {
      actorId,
      action: 'add_order_item',
      entityType: 'Order',
      entityId: orderId,
      diff: { productId: input.productId, productName: product.name, quantity: input.quantity, unitPrice: input.unitPrice },
    });

    return tx.order.findUnique({
      where: { id: orderId },
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
  });
}

const TERMINAL_SHIPMENT_STATUSES = ['Delivered', 'Returned', 'Cancelled'];
const STOCK_DEDUCTED_STATUS = 'Ready for Dispatch';

export async function updateOrderItemQuantity(
  orderId: string,
  orderItemId: string,
  newQuantity: number,
  actorId: string,
  newUnitPrice?: number
) {
  return prisma.$transaction(async (tx: Tx) => {
    // Load the order item with its order, product, and all shipment items (with shipment status)
    const item = await tx.orderItem.findUnique({
      where: { id: orderItemId },
      include: {
        order: { include: { retailer: true } },
        product: true,
        shipmentItems: { include: { shipment: true } },
      },
    });
    if (!item || item.orderId !== orderId) throw AppError.notFound('Order item');

    if (item.order.isDirectSale) {
      throw AppError.badRequest('Quantities cannot be edited on direct sale orders', 'VALIDATION_ERROR');
    }

    const deliveredQty = item.deliveredQuantity ?? 0;
    if (newQuantity < deliveredQty) {
      throw AppError.badRequest(
        `Cannot reduce below already-delivered quantity (${deliveredQty})`,
        'INVALID_QUANTITY'
      );
    }

    const delta = newQuantity - item.quantity;
    if (delta === 0) return item; // no-op

    type SiWithShipment = (typeof item.shipmentItems)[0];
    const activeItems = item.shipmentItems.filter(
      (si: SiWithShipment) => !TERMINAL_SHIPMENT_STATUSES.includes(si.shipment.status)
    );
    const sumActive = activeItems.reduce((s: number, si: SiWithShipment) => s + si.quantity, 0);

    if (activeItems.length === 0) {
      throw AppError.badRequest('All shipments are in a terminal state — quantity cannot be changed', 'VALIDATION_ERROR');
    }
    if (delta < 0 && -delta > sumActive) {
      throw AppError.badRequest(
        `Cannot reduce by ${-delta}: only ${sumActive} units remain in active shipments`,
        'INVALID_QUANTITY'
      );
    }

    const pendingItems = activeItems.filter((si: SiWithShipment) => si.shipment.status !== STOCK_DEDUCTED_STATUS);
    const readyItems  = activeItems.filter((si: SiWithShipment) => si.shipment.status === STOCK_DEDUCTED_STATUS);

    let remaining = delta; // positive = add, negative = remove

    if (remaining < 0) {
      // ── Reduce: drain pending items first (no stock change), then ready items (restore stock) ──
      for (const si of [...pendingItems, ...readyItems]) {
        if (remaining === 0) break;
        const isReady = si.shipment.status === STOCK_DEDUCTED_STATUS;
        const canReduce = Math.min(si.quantity, -remaining);
        const newQty = si.quantity - canReduce;

        if (newQty === 0) {
          await tx.shipmentItem.delete({ where: { id: si.id } });
          const leftInShipment = await tx.shipmentItem.count({ where: { shipmentId: si.shipmentId } });
          if (leftInShipment === 0) {
            // Directly cancel the now-empty shipment (stock already restored per item above)
            await tx.shipment.update({ where: { id: si.shipmentId }, data: { status: 'Cancelled' } });
          }
        } else {
          await tx.shipmentItem.update({ where: { id: si.id }, data: { quantity: newQty } });
        }

        if (isReady) {
          await tx.product.update({
            where: { id: item.productId },
            data: { stockQuantity: { increment: canReduce } },
          });
        }

        remaining += canReduce; // remaining is negative; adding positive moves it toward 0
      }
    } else {
      // ── Increase: fill first pending item (free), else first ready item (deduct stock) ──
      const target = pendingItems[0] ?? readyItems[0];

      if (target.shipment.status === STOCK_DEDUCTED_STATUS) {
        const stock = item.product.stockQuantity;
        if (stock < remaining) {
          throw AppError.badRequest(
            `Insufficient stock for "${item.product.name}" (available: ${stock}, needed: ${remaining})`,
            'INSUFFICIENT_STOCK'
          );
        }
        await tx.product.update({
          where: { id: item.productId },
          data: { stockQuantity: { decrement: remaining } },
        });
      }

      await tx.shipmentItem.update({
        where: { id: target.id },
        data: { quantity: target.quantity + remaining },
      });
    }

    // ── Update order total and retailer pendingCollection ─────────────────────
    // Combined delta covers both qty and price changes in one shot
    const oldPrice = Number(item.unitPrice);
    const finalPrice = newUnitPrice ?? oldPrice;
    const totalDelta = newQuantity * finalPrice - item.quantity * oldPrice;
    await tx.order.update({
      where: { id: orderId },
      data: { totalAmount: { increment: totalDelta } },
    });
    const itemCompanyId = item.order.overrideCompanyId ?? item.product.companyId;
    const afterQtyChange = await tx.retailer.update({
      where: { id: item.order.retailerId },
      data: { pendingCollection: { increment: totalDelta } },
    });
    await writeRetailerLedger(tx, {
      retailerId: item.order.retailerId,
      companyId: itemCompanyId,
      delta: totalDelta,
      balanceAfter: Number(afterQtyChange.pendingCollection),
      type: 'qty_adjusted',
      referenceType: 'Order',
      referenceId: orderId,
      actorId,
    });
    await adjustCompanyBalance(tx, item.order.retailerId, itemCompanyId, totalDelta);

    // ── Update order item ─────────────────────────────────────────────────────
    await tx.orderItem.update({
      where: { id: orderItemId },
      data: { quantity: newQuantity, ...(newUnitPrice != null && { unitPrice: newUnitPrice }) },
    });

    await writeAuditLog(tx, {
      actorId,
      action: 'update_order_item_qty',
      entityType: 'Order',
      entityId: orderId,
      diff: { orderItemId, productName: item.product.name, from: item.quantity, to: newQuantity },
    });

    return tx.orderItem.findUnique({
      where: { id: orderItemId },
      include: { product: true, shipmentItems: { include: { shipment: true } } },
    });
  });
}

export async function listOrders(params: {
  cursor?: string;
  limit: number;
  retailerId?: string;
  salesOfficerId?: string;
  assignedSalesOfficerId?: string;
  search?: string;
}) {
  const where = {
    ...(params.retailerId && { retailerId: params.retailerId }),
    ...(params.salesOfficerId && { salesOfficerId: params.salesOfficerId }),
    ...(params.assignedSalesOfficerId && {
      retailer: { salesOfficers: { some: { salesOfficerId: params.assignedSalesOfficerId } } },
    }),
    ...(params.search && {
      retailer: { name: { contains: params.search, mode: 'insensitive' as const } },
    }),
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

export async function updateOrderNotes(id: string, notes: string | null | undefined) {
  const order = await prisma.order.findUnique({ where: { id } });
  if (!order) throw AppError.notFound('Order');
  return prisma.order.update({ where: { id }, data: { notes: notes ?? null } });
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
