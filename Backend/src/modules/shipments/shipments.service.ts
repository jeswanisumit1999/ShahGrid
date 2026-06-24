import { Prisma } from '@prisma/client';
import { prisma } from '../../lib/prisma';
import { AppError } from '../../errors/AppError';
import { buildPrismaPage, buildPaginationResult } from '../../utils/pagination';
import { writeAuditLog } from '../../utils/audit';
import { writeStockLedger } from '../../utils/stockLedger';
import { writeRetailerLedger } from '../../utils/retailerLedger';
import { adjustCompanyBalance } from '../../utils/companyBalance';

/**
 * Role-gated transition table.
 *
 * Key lifecycle rule:
 *   → Ready for Dispatch : stock is RESERVED (deducted from stockQuantity)
 *   → Cancelled (from Ready for Dispatch) : stock is RESTORED
 *   → Delivered : actual delivered quantities recorded; adjustments restore leftover stock
 *   → Returned : all delivered stock is restored; order total reduced
 */
function getAllowedNext(permissions: string[], currentStatus: string): string[] {
  const result: string[] = [];
  const pending = ['Pending Stock Verification', 'Pending Stock Availability'];
  if (pending.includes(currentStatus)) {
    if (permissions.includes('shipments.verify')) result.push('Ready for Dispatch');
    if (permissions.includes('shipments.cancel')) result.push('Cancelled');
  }
  if (currentStatus === 'Ready for Dispatch') {
    if (permissions.includes('shipments.deliver')) result.push('Delivered');
    if (permissions.includes('shipments.cancel')) result.push('Cancelled');
  }
  if (currentStatus === 'Delivered') {
    if (permissions.includes('shipments.return')) result.push('Returned');
  }
  return result;
}

type ShipmentItemAdjustment = { shipmentItemId: string; actualQuantity: number };

export async function updateShipmentStatus(
  shipmentId: string,
  newStatus: string,
  notes: string | undefined,
  actorId: string,
  actorPermissions: string[],
  adjustments?: ShipmentItemAdjustment[],
  force?: boolean
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

    const allowedNext = getAllowedNext(actorPermissions, shipment.status);
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
        if (newStock < 0 && !force) {
          throw AppError.badRequest(
            `Insufficient stock for "${product.name}" (available: ${product.stockQuantity}, needed: ${item.quantity})`,
            'INSUFFICIENT_STOCK'
          );
        }
        await tx.product.update({
          where: { id: product.id },
          data: { stockQuantity: newStock },
        });
        await writeStockLedger(tx, {
          productId: product.id,
          delta: -item.quantity,
          balanceAfter: newStock,
          type: 'dispatch_out',
          referenceType: 'Shipment',
          referenceId: shipmentId,
          actorId,
        });
      }
    }

    // ── Cancelled: restore stock if it was already reserved ───────────────────
    if (newStatus === 'Cancelled' && shipment.status === 'Ready for Dispatch') {
      for (const item of shipment.shipmentItems) {
        const updated = await tx.product.update({
          where: { id: item.orderItem.product.id },
          data: { stockQuantity: { increment: item.quantity } },
        });
        await writeStockLedger(tx, {
          productId: item.orderItem.product.id,
          delta: item.quantity,
          balanceAfter: updated.stockQuantity,
          type: 'dispatch_cancel_in',
          referenceType: 'Shipment',
          referenceId: shipmentId,
          actorId,
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
          const updated = await tx.product.update({
            where: { id: item.orderItem.product.id },
            data: { stockQuantity: { increment: reduced } },
          });
          await writeStockLedger(tx, {
            productId: item.orderItem.product.id,
            delta: reduced,
            balanceAfter: updated.stockQuantity,
            type: 'delivery_short_in',
            referenceType: 'Shipment',
            referenceId: shipmentId,
            actorId,
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
        const afterShortfall = await tx.retailer.update({
          where: { id: shipment.order.retailerId },
          data: { pendingCollection: { decrement: totalOrderReduction } },
        });
        await adjustCompanyBalance(tx, shipment.order.retailerId, shipment.companyId, -totalOrderReduction);
        await writeRetailerLedger(tx, {
          retailerId: shipment.order.retailerId,
          companyId: shipment.companyId,
          delta: -totalOrderReduction,
          balanceAfter: Number(afterShortfall.pendingCollection),
          type: 'delivery_adjustment',
          referenceType: 'Shipment',
          referenceId: shipmentId,
          actorId,
        });
      }
    }

    // ── Returned: restore all delivered stock, reduce order total ─────────────
    if (newStatus === 'Returned') {
      updateData.returnedAt = new Date();

      let returnedAmount = 0;
      for (const item of shipment.shipmentItems) {
        if (item.status === 'delivered' && item.quantity > 0) {
          const updated = await tx.product.update({
            where: { id: item.orderItem.product.id },
            data: { stockQuantity: { increment: item.quantity } },
          });
          await writeStockLedger(tx, {
            productId: item.orderItem.product.id,
            delta: item.quantity,
            balanceAfter: updated.stockQuantity,
            type: 'shipment_return_in',
            referenceType: 'Shipment',
            referenceId: shipmentId,
            actorId,
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
        const afterReturn = await tx.retailer.update({
          where: { id: shipment.order.retailerId },
          data: { pendingCollection: { decrement: returnedAmount } },
        });
        await adjustCompanyBalance(tx, shipment.order.retailerId, shipment.companyId, -returnedAmount);
        await writeRetailerLedger(tx, {
          retailerId: shipment.order.retailerId,
          companyId: shipment.companyId,
          delta: -returnedAmount,
          balanceAfter: Number(afterReturn.pendingCollection),
          type: 'shipment_return',
          referenceType: 'Shipment',
          referenceId: shipmentId,
          actorId,
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
  items: { id: string; quantity?: number }[],
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
    const invalidIds = items.filter((i) => !allItemIds.includes(i.id));
    if (invalidIds.length > 0) {
      throw AppError.badRequest('Some item IDs do not belong to this shipment', 'INVALID_ITEMS');
    }

    // Validate quantities and ensure something remains in the original
    const totalOriginal = shipment.shipmentItems.reduce((sum, i) => sum + i.quantity, 0);
    let totalMoved = 0;
    for (const item of items) {
      const original = shipment.shipmentItems.find((i) => i.id === item.id)!;
      const moveQty = item.quantity ?? original.quantity;
      if (moveQty > original.quantity) {
        throw AppError.badRequest(`Move quantity exceeds available quantity for item ${item.id}`, 'INVALID_QUANTITY');
      }
      totalMoved += moveQty;
    }
    if (totalMoved >= totalOriginal) {
      throw AppError.badRequest('Must keep at least one unit in the original shipment', 'SPLIT_TOO_MANY');
    }

    // Create the new child shipment
    const newShipment = await tx.shipment.create({
      data: {
        orderId: shipment.orderId,
        companyId: shipment.companyId,
        status: shipment.status,
      },
    });

    // Move items — full move or partial quantity split
    for (const item of items) {
      const original = shipment.shipmentItems.find((i) => i.id === item.id)!;
      const moveQty = item.quantity ?? original.quantity;

      if (moveQty >= original.quantity) {
        // Move the entire item
        await tx.shipmentItem.update({
          where: { id: item.id },
          data: { shipmentId: newShipment.id },
        });
      } else {
        // Partial split: reduce original, create new item in new shipment
        await tx.shipmentItem.update({
          where: { id: item.id },
          data: { quantity: original.quantity - moveQty },
        });
        await tx.shipmentItem.create({
          data: {
            shipmentId: newShipment.id,
            orderItemId: original.orderItemId,
            quantity: moveQty,
          },
        });
      }
    }

    await writeAuditLog(tx, {
      actorId,
      action: 'split_shipment',
      entityType: 'Shipment',
      entityId: shipmentId,
      diff: { newShipmentId: newShipment.id, movedItems: items },
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
