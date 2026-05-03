import { Prisma } from '@prisma/client';
import { prisma } from '../../lib/prisma';
import { AppError } from '../../errors/AppError';
import { buildPrismaPage, buildPaginationResult } from '../../utils/pagination';
import { writeAuditLog } from '../../utils/audit';

export async function listCompanies() {
  return prisma.company.findMany({ where: { isActive: true }, orderBy: { name: 'asc' } });
}

export async function createCompany(name: string) {
  const existing = await prisma.company.findUnique({ where: { name } });
  if (existing) throw AppError.conflict(`Company "${name}" already exists`);
  return prisma.company.create({ data: { name } });
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
}) {
  if (data.sku) {
    const existing = await prisma.product.findUnique({ where: { sku: data.sku } });
    if (existing) throw AppError.conflict('A product with this SKU already exists');
  }
  return prisma.product.create({ data });
}

export async function updateProduct(id: string, data: Partial<{
  companyId: string;
  categoryId: string;
  name: string;
  brand: string;
  price: number;
  stockQuantity: number;
}>) {
  const product = await prisma.product.findUnique({ where: { id } });
  if (!product) throw AppError.notFound('Product');
  return prisma.product.update({ where: { id }, data });
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
