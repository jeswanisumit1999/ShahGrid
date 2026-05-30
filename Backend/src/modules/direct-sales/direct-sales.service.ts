import { prisma } from '../../lib/prisma';
import { AppError } from '../../errors/AppError';
import { buildPrismaPage, buildPaginationResult } from '../../utils/pagination';
import { writeStockLedger } from '../../utils/stockLedger';
import { writeAuditLog } from '../../utils/audit';
import { drawChallan, claimChallanNumber, makePdfDoc, Tx, CompanyInfo } from '../../utils/challanPdf';

export async function createDirectSale(data: {
  customerName: string;
  salesOfficerId: string;
  createdById: string;
  amountPaid?: number;
  notes?: string;
  items: { productId: string; quantity: number; unitPrice: number }[];
}) {
  return prisma.$transaction(async (tx) => {
    // Verify stock for all items upfront
    for (const item of data.items) {
      const product = await tx.product.findUnique({ where: { id: item.productId } });
      if (!product) throw AppError.notFound('Product');
      if (!product.isActive) throw AppError.badRequest(`Product "${product.name}" is not active`);
      if (product.stockQuantity < item.quantity) {
        throw AppError.badRequest(
          `Insufficient stock for "${product.name}" (available: ${product.stockQuantity})`,
          'INSUFFICIENT_STOCK',
        );
      }
    }

    const totalAmount = data.items.reduce((s, i) => s + i.quantity * i.unitPrice, 0);

    const sale = await tx.directSale.create({
      data: {
        customerName: data.customerName,
        salesOfficerId: data.salesOfficerId,
        createdById: data.createdById,
        totalAmount,
        amountPaid: data.amountPaid,
        notes: data.notes,
        items: {
          create: data.items.map((i) => ({
            productId: i.productId,
            quantity: i.quantity,
            unitPrice: i.unitPrice,
          })),
        },
      },
      include: {
        items: { include: { product: { select: { name: true, sku: true } } } },
        salesOfficer: { select: { id: true, name: true } },
      },
    });

    // Deduct stock + write ledger for each item
    for (const item of data.items) {
      const product = await tx.product.findUnique({ where: { id: item.productId } });
      const newStock = product!.stockQuantity - item.quantity;

      await tx.product.update({
        where: { id: item.productId },
        data: { stockQuantity: newStock },
      });

      await writeStockLedger(tx, {
        productId: item.productId,
        delta: -item.quantity,
        balanceAfter: newStock,
        type: 'direct_sale',
        referenceType: 'DirectSale',
        referenceId: sale.id,
        actorId: data.createdById,
      });
    }

    await writeAuditLog(tx, {
      actorId: data.createdById,
      action: 'create_direct_sale',
      entityType: 'DirectSale',
      entityId: sale.id,
      diff: {
        customerName: data.customerName,
        totalAmount,
        itemCount: data.items.length,
      },
    });

    return sale;
  });
}

export async function listDirectSales(params: {
  cursor?: string;
  limit: number;
  salesOfficerId?: string;
  search?: string;
}) {
  const sales = await prisma.directSale.findMany({
    where: {
      ...(params.salesOfficerId && { salesOfficerId: params.salesOfficerId }),
      ...(params.search && { customerName: { contains: params.search, mode: 'insensitive' } }),
    },
    orderBy: { createdAt: 'desc' },
    ...buildPrismaPage(params),
    include: {
      salesOfficer: { select: { id: true, name: true } },
      items: { include: { product: { select: { name: true, sku: true } } } },
    },
  });
  return buildPaginationResult(sales, params.limit);
}

export async function getDirectSaleById(id: string) {
  const sale = await prisma.directSale.findUnique({
    where: { id },
    include: {
      salesOfficer: { select: { id: true, name: true } },
      createdBy: { select: { id: true, name: true } },
      items: {
        include: {
          product: {
            include: {
              company: { select: { name: true, address: true, phone: true, gstin: true } },
            },
          },
        },
      },
    },
  });
  if (!sale) throw AppError.notFound('Direct Sale');
  return sale;
}

export async function generateDirectSaleChallanPdf(id: string): Promise<Buffer> {
  const sale = await getDirectSaleById(id);

  const challanNo = sale.challanNumber ??
    await prisma.$transaction((tx: Tx) => claimChallanNumber(tx, 'direct_sale', id));

  const company: CompanyInfo =
    sale.items[0]?.product?.company ??
    { name: 'N/A', address: null, phone: null, gstin: null };

  const items = sale.items.map((si) => ({
    description: si.product.name,
    quantity: si.quantity,
    rate: Number(si.unitPrice),
  }));

  const { doc, finish } = makePdfDoc();

  drawChallan(doc, {
    challanNo,
    date: sale.createdAt,
    company,
    recipientName: sale.customerName,
    recipientGstin: null,
    items,
    notes: sale.notes ?? null,
  });

  return finish();
}
