import { Prisma } from '@prisma/client';
import { prisma } from '../../lib/prisma';
import { AppError } from '../../errors/AppError';
import { buildPrismaPage, buildPaginationResult } from '../../utils/pagination';
import { writeAuditLog } from '../../utils/audit';
import { writeStockLedger } from '../../utils/stockLedger';

export async function listCompanies() {
  return prisma.company.findMany({ where: { isActive: true }, orderBy: { name: 'asc' } });
}

export async function createCompany(name: string, gstin?: string, phone?: string, address?: string) {
  const existing = await prisma.company.findUnique({ where: { name } });
  if (existing) throw AppError.conflict(`Company "${name}" already exists`);
  return prisma.company.create({
    data: {
      name,
      ...(gstin ? { gstin } : {}),
      ...(phone ? { phone } : {}),
      ...(address ? { address } : {}),
    },
  });
}

export async function listCategories() {
  return prisma.category.findMany({ where: { isActive: true }, orderBy: { name: 'asc' } });
}

export async function createCategory(name: string) {
  const existing = await prisma.category.findUnique({ where: { name } });
  if (existing) throw AppError.conflict(`Category "${name}" already exists`);
  return prisma.category.create({ data: { name } });
}

export async function listProducts(params: {
  cursor?: string;
  limit: number;
  search?: string;
  companyId?: string;
  categoryId?: string;
}) {
  const where: Prisma.ProductWhereInput = {
    isActive: true,
    ...(params.companyId && { companyId: params.companyId }),
    ...(params.categoryId && { categoryId: params.categoryId }),
    ...(params.search && {
      OR: [
        { name: { contains: params.search, mode: 'insensitive' } },
        { sku: { contains: params.search, mode: 'insensitive' } },
        { brand: { contains: params.search, mode: 'insensitive' } },
        { company: { name: { contains: params.search, mode: 'insensitive' } } },
      ],
    }),
  };

  const products = await prisma.product.findMany({
    where,
    orderBy: { createdAt: 'asc' },
    ...buildPrismaPage(params),
    include: { company: true, category: true },
  });

  return buildPaginationResult(products, params.limit);
}

export async function getProductById(id: string) {
  const product = await prisma.product.findUnique({
    where: { id },
    include: { company: true, category: true },
  });
  if (!product) throw AppError.notFound('Product');
  return product;
}

export async function listBrands(): Promise<string[]> {
  const rows = await prisma.product.findMany({
    where: { brand: { not: null }, isActive: true },
    select: { brand: true },
    distinct: ['brand'],
    orderBy: { brand: 'asc' },
  });
  return rows.map((r) => r.brand).filter((b): b is string => b !== null);
}

export async function createProduct(data: {
  companyId: string;
  categoryId?: string;
  name: string;
  sku?: string;
  brand?: string;
  price: number;
  stockQuantity: number;
  lowStockThreshold?: number;
}) {
  return prisma.product.create({ data });
}

export async function updateProduct(id: string, data: Partial<{
  companyId: string;
  categoryId: string;
  name: string;
  brand: string;
  price: number;
  stockQuantity: number;
  lowStockThreshold: number | null;
}>) {
  const product = await prisma.product.findUnique({ where: { id } });
  if (!product) throw AppError.notFound('Product');
  return prisma.product.update({ where: { id }, data });
}

export async function deleteProduct(id: string) {
  const product = await prisma.product.findUnique({ where: { id } });
  if (!product) throw AppError.notFound('Product');
  if (!product.isActive) throw AppError.conflict('Product is already deleted');
  return prisma.product.update({ where: { id }, data: { isActive: false } });
}

export async function adjustStock(
  productId: string,
  delta: number,
  reason: string | undefined,
  actorId: string
) {
  return prisma.$transaction(async (tx) => {
    const product = await tx.product.findUnique({ where: { id: productId } });
    if (!product) throw AppError.notFound('Product');

    const newStock = product.stockQuantity + delta;
    if (newStock < 0) {
      throw AppError.badRequest(
        `Adjustment would result in negative stock (current: ${product.stockQuantity}, delta: ${delta})`,
        'INSUFFICIENT_STOCK'
      );
    }

    const updated = await tx.product.update({
      where: { id: productId },
      data: { stockQuantity: newStock },
    });

    await tx.stockAdjustment.create({
      data: {
        productId,
        adjustedBy: actorId,
        delta,
        stockBefore: product.stockQuantity,
        stockAfter: newStock,
        reason,
      },
    });

    await writeStockLedger(tx, {
      productId,
      delta,
      balanceAfter: newStock,
      type: delta > 0 ? 'manual_in' : 'manual_out',
      notes: reason,
      actorId,
    });

    await writeAuditLog(tx, {
      actorId,
      action: 'adjust_stock',
      entityType: 'Product',
      entityId: productId,
      diff: { delta, stockBefore: product.stockQuantity, stockAfter: newStock, reason },
    });

    return updated;
  });
}

export async function getStockLedger(productId: string, params: {
  cursor?: string;
  limit: number;
  direction?: 'in' | 'out';
}) {
  const product = await prisma.product.findUnique({
    where: { id: productId },
    include: { company: { select: { name: true } } },
  });
  if (!product) throw AppError.notFound('Product');

  const where = {
    productId,
    ...(params.direction === 'in'  && { delta: { gt: 0 } }),
    ...(params.direction === 'out' && { delta: { lt: 0 } }),
  };

  const entries = await prisma.stockLedger.findMany({
    where,
    orderBy: { createdAt: 'desc' },
    ...buildPrismaPage(params),
  });

  const result = buildPaginationResult(entries, params.limit);

  // Enrich with actor names (loose FK — manual join)
  const actorIds = [...new Set(result.items.map((e) => e.actorId).filter(Boolean))] as string[];
  const actors = actorIds.length
    ? await prisma.user.findMany({ where: { id: { in: actorIds } }, select: { id: true, name: true } })
    : [];
  const actorMap = Object.fromEntries(actors.map((a) => [a.id, a.name]));

  return {
    product,
    items: result.items.map((e) => ({
      ...e,
      actorName: e.actorId ? (actorMap[e.actorId] ?? null) : null,
    })),
    hasMore: result.hasMore,
    nextCursor: result.nextCursor,
  };
}
