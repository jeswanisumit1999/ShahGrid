import { prisma } from '../../lib/prisma';
import { AppError } from '../../errors/AppError';
import { drawChallan, claimChallanNumber, makePdfDoc, Tx, CompanyInfo } from '../../utils/challanPdf';

export async function generateChallanPdf(orderId: string): Promise<Buffer> {
  const order = await prisma.order.findUnique({
    where: { id: orderId },
    include: {
      retailer: { select: { name: true, gstin: true } },
      overrideCompany: { select: { name: true, address: true, phone: true, gstin: true } },
      orderItems: {
        include: {
          product: {
            include: {
              company: { select: { name: true, address: true, phone: true, gstin: true } },
            },
          },
        },
      },
      shipments: {
        include: {
          company: { select: { name: true, address: true, phone: true, gstin: true } },
          shipmentItems: {
            include: {
              orderItem: {
                include: { product: { select: { name: true, sku: true } } },
              },
            },
          },
        },
        orderBy: { createdAt: 'asc' },
      },
    },
  });

  if (!order) throw AppError.notFound('Order');

  // Resolve challan numbers before entering the PDF Promise.
  // Reuse any previously assigned number; only claim a new one on first generation.
  let orderChallanNo: string | undefined;
  const shipmentChallanNos = new Map<string, string>();

  if (order.isDirectSale || order.shipments.length === 0) {
    orderChallanNo = order.challanNumber ??
      await prisma.$transaction((tx: Tx) => claimChallanNumber(tx, 'order', order.id));
  } else {
    for (const shipment of order.shipments) {
      shipmentChallanNos.set(
        shipment.id,
        shipment.challanNumber ??
          await prisma.$transaction((tx: Tx) => claimChallanNumber(tx, 'shipment', shipment.id)),
      );
    }
  }

  const { doc, finish } = makePdfDoc();

  const commonOpts = {
    date: order.createdAt,
    recipientName: order.retailer.name,
    recipientGstin: order.retailer.gstin ?? null,
    notes: order.notes,
  };

  if (order.isDirectSale || order.shipments.length === 0) {
    const company: CompanyInfo =
      order.overrideCompany ??
      order.orderItems[0]?.product?.company ??
      { name: 'N/A', address: null, phone: null, gstin: null };

    const items = order.orderItems.map((oi: typeof order.orderItems[number]) => ({
      description: oi.product.name,
      quantity: oi.quantity,
      rate: Number(oi.unitPrice),
    }));

    drawChallan(doc, { ...commonOpts, challanNo: orderChallanNo!, company, items });
  } else {
    for (const shipment of order.shipments) {
      const items = shipment.shipmentItems.map((si: typeof shipment.shipmentItems[number]) => ({
        description: si.orderItem.product.name,
        quantity: si.quantity,
        rate: Number(si.orderItem.unitPrice),
      }));

      drawChallan(doc, { ...commonOpts, challanNo: shipmentChallanNos.get(shipment.id)!, company: shipment.company, items });
    }
  }

  return finish();
}
