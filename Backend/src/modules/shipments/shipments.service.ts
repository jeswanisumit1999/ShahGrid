import { Prisma } from '@prisma/client';
import { prisma } from '../../lib/prisma';
import { AppError } from '../../errors/AppError';
import { buildPrismaPage, buildPaginationResult } from '../../utils/pagination';
import { writeAuditLog } from '../../utils/audit';

/**
 * Role-gated transition table.
 *
 * Key lifecycle rule:
 *   → Ready for Dispatch : stock is RESERVED (deducted from stockQuantity)
 *   → Cancelled (from Ready for Dispatch) : stock is RESTORED
 *   → Delivered : actual delivered quantities recorded; adjustments restore leftover stock
 *   → Returned : all delivered stock is restored; order total reduced
 */
const ALLOWED_TRANSITIONS: Record<string, Record<string, string[]>> = {
  Admin: {
    'Pending Stock Verification': ['Ready for Dispatch', 'Cancelled'],
    'Pending Stock Availability': ['Ready for Dispatch', 'Cancelled'],
    'Ready for Dispatch': ['Delivered', 'Cancelled'],
    Delivered: ['Returned'],
  },
  'Supply Chain': {
    'Pending Stock Verification': ['Ready for Dispatch', 'Cancelled'],
    'Pending Stock Availability': ['Ready for Dispatch', 'Cancelled'],
    'Ready for Dispatch': ['Cancelled'],
  },
  'Godown Manager': {
    'Pending Stock Verification': ['Ready for Dispatch'],
    'Pending Stock Availability': ['Ready for Dispatch'],
    'Ready for Dispatch': ['Delivered'],
  },
};

function getAllowedNext(roles: string[], currentStatus: string): string[] {
  const allowed = new Set<string>();
  for (const role of roles) {
    const transitions = ALLOWED_TRANSITIONS[role]?.[currentStatus] ?? [];
    transitions.forEach((t) => allowed.add(t));
  }
  return [...allowed];
}

type ShipmentItemAdjustment = { shipmentItemId: string; actualQuantity: number };

export async function updateShipmentStatus(
  shipmentId: string,
  newStatus: string,
  notes: string | undefined,
  actorId: string,
  actorRoles: string[],
  adjustments?: ShipmentItemAdjustment[]
) {
  return prisma.$transaction(async (tx) => {
    const shipment = await tx.shipment.findUnique({
      where: { id: shipmentId },
      include: {
        shipmentItems: { include: { orderItem: { include: { product: true } } } },
        order: true,
      },
    });
    if (!shipment) throw AppError.notFound('Shipment');

    const allowedNext = getAllowedNext(actorRoles, shipment.status);
    if (!allowedNext.includes(newStatus)) {
      throw AppError.badRequest(
        `Transition from "${shipment.status}" to "${newStatus}" is not allowed for your role`,
        'INVALID_STATUS_TRANSITION'
      );
    }

    const updateData: Prisma.ShipmentUpdateInput = {
      status: newStatus,
      notes: notes ?? shipment.notes,
    };

    // ── Ready for Dispatch: reserve stock ─────────────────────────────────────
    if (newStatus === 'Ready for Dispatch') {
      updateData.readyAt = new Date();

      for (const item of shipment.shipmentItems) {
        const product = item.orderItem.product;
        const newStock = product.stockQuantity - item.quantity;
        if (newStock < 0) {
          throw AppError.badRequest(
            `Insufficient stock for "${product.name}" (available: ${product.stockQuantity}, needed: ${item.quantity})`,
            'INSUFFICIENT_STOCK'
          );
        }
        await tx.product.update({
          where: { id: product.id },
          data: { stockQuantity: newStock },
        });
      }
    }

    // ── Cancelled: restore stock if it was already reserved ───────────────────
    if (newStatus === 'Cancelled' && shipment.status === 'Ready for Dispatch') {
      for (const item of shipment.shipmentItems) {
        await tx.product.update({
          where: { id: item.orderItem.product.id },
          data: { stockQuantity: { increment: item.quantity } },
        });
      }
    }

    // ── Delivered: apply per-item adjustments, record delivered quantities ────
    if (newStatus === 'Delivered') {
      updateData.deliveredAt = new Date();

      const adjMap = new Map(
        (adjustments ?? []).map((a) => [a.shipmentItemId, a.actualQuantity])
      );

      let totalOrderReduction = 0;

      for (const item of shipment.shipmentItems) {
        const planned = item.quantity;
        const actual = adjMap.has(item.id) ? adjMap.get(item.id)! : planned;
        const reduced = planned - actual; // stock to give back (shortfall)

        if (actual < 0 || actual > planned) {
          throw AppError.badRequest(
            `Actual quantity for item ${item.id} must be between 0 and ${planned}`,
            'INVALID_QUANTITY'
          );
        }

        // Restore stock for undelivered portion
        if (reduced > 0) {
          await tx.product.update({
            where: { id: item.orderItem.product.id },
            data: { stockQuantity: { increment: reduced } },
          });
          totalOrderReduction += reduced * Number(item.orderItem.unitPrice);
        }

        // Update shipment item to actual quantity
        await tx.shipmentItem.update({
          where: { id: item.id },
          data: { quantity: actual, status: actual > 0 ? 'delivered' : 'undelivered' },
        });

        // Record delivered quantity on the order item
        await tx.orderItem.update({
          where: { id: item.orderItemId },
          data: { deliveredQuantity: { increment: actual } },
        });
      }

      // Reduce order total and retailer pendingCollection for any shortfall
      if (totalOrderReduction > 0) {
        await tx.order.update({
          where: { id: shipment.orderId },
          data: { totalAmount: { decrement: totalOrderReduction } },
        });
        await tx.retailer.update({
          where: { id: shipment.order.retailerId },
          data: { pendingCollection: { decrement: totalOrderReduction } },
        });
      }
    }

    // ── Returned: restore all delivered stock, reduce order total ─────────────
    if (newStatus === 'Returned') {
      updateData.returnedAt = new Date();

      let returnedAmount = 0;
      for (const item of shipment.shipmentItems) {
        if (item.status === 'delivered' && item.quantity > 0) {
          await tx.product.update({
            where: { id: item.orderItem.product.id },
            data: { stockQuantity: { increment: item.quantity } },
          });
          await tx.shipmentItem.update({
            where: { id: item.id },
            data: { status: 'returned' },
          });
          await tx.orderItem.update({
            where: { id: item.orderItemId },
            data: { deliveredQuantity: { decrement: item.quantity } },
          });
          returnedAmount += item.quantity * Number(item.orderItem.unitPrice);
        }
      }

      if (returnedAmount > 0) {
        await tx.order.update({
          where: { id: shipment.orderId },
          data: { totalAmount: { decrement: returnedAmount } },
        });
        await tx.retailer.update({
          where: { id: shipment.order.retailerId },
          data: { pendingCollection: { decrement: returnedAmount } },
        });
      }
    }

    const updated = await tx.shipment.update({ where: { id: shipmentId }, data: updateData });

    await writeAuditLog(tx, {
      actorId,
      action: 'update_shipment_status',
      entityType: 'Shipment',
      entityId: shipmentId,
      diff: { from: shipment.status, to: newStatus, adjustments: adjustments ?? [] },
    });

    return updated;
  });
}

export async function splitShipment(
  shipmentId: string,
  itemIds: string[],
  actorId: string
) {
  return prisma.$transaction(async (tx) => {
    const shipment = await tx.shipment.findUnique({
      where: { id: shipmentId },
      include: { shipmentItems: true },
    });
    if (!shipment) throw AppError.notFound('Shipment');

    const splittableStatuses = ['Pending Stock Verification', 'Pending Stock Availability'];
    if (!splittableStatuses.includes(shipment.status)) {
      throw AppError.badRequest(
        `Cannot split a shipment in "${shipment.status}" status`,
        'INVALID_SPLIT_STATUS'
      );
    }

    const allItemIds = shipment.shipmentItems.map((i) => i.id);
    const invalidIds = itemIds.filter((id) => !allItemIds.includes(id));
    if (invalidIds.length > 0) {
      throw AppError.badRequest('Some item IDs do not belong to this shipment', 'INVALID_ITEMS');
    }
    if (itemIds.length >= allItemIds.length) {
      throw AppError.badRequest('Must keep at least one item in the original shipment', 'SPLIT_TOO_MANY');
    }

    // Create the new child shipment
    const newShipment = await tx.shipment.create({
      data: {
        orderId: shipment.orderId,
        companyId: shipment.companyId,
        status: shipment.status,
      },
    });

    // Move selected items to the new shipment
    await tx.shipmentItem.updateMany({
      where: { id: { in: itemIds } },
      data: { shipmentId: newShipment.id },
    });

    await writeAuditLog(tx, {
      actorId,
      action: 'split_shipment',
      entityType: 'Shipment',
      entityId: shipmentId,
      diff: { newShipmentId: newShipment.id, movedItemIds: itemIds },
    });

    return { original: shipment, newShipment };
  });
}

export async function listShipments(params: {
  cursor?: string;
  limit: number;
  orderId?: string;
  status?: string;
  companyId?: string;
}) {
  const where: Prisma.ShipmentWhereInput = {
    ...(params.orderId && { orderId: params.orderId }),
    ...(params.status && { status: params.status }),
    ...(params.companyId && { companyId: params.companyId }),
  };

  const shipments = await prisma.shipment.findMany({
    where,
    orderBy: { createdAt: 'desc' },
    ...buildPrismaPage(params),
    include: {
      company: { select: { id: true, name: true } },
      order: { select: { id: true, retailer: { select: { id: true, name: true } } } },
      shipmentItems: {
        include: {
          orderItem: { include: { product: { select: { id: true, name: true, sku: true } } } },
        },
      },
    },
  });

  return buildPaginationResult(shipments, params.limit);
}

export async function getShipmentById(id: string) {
  const shipment = await prisma.shipment.findUnique({
    where: { id },
    include: {
      company: true,
      order: { include: { retailer: true } },
      shipmentItems: {
        include: { orderItem: { include: { product: true } } },
      },
    },
  });
  if (!shipment) throw AppError.notFound('Shipment');
  return shipment;
}
