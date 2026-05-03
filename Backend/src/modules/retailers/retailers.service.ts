import { Prisma } from '@prisma/client';
import { prisma } from '../../lib/prisma';
import { AppError } from '../../errors/AppError';
import { buildPrismaPage, buildPaginationResult } from '../../utils/pagination';
import { writeAuditLog } from '../../utils/audit';

export async function listRetailers(params: {
  cursor?: string;
  limit: number;
  search?: string;
  salesOfficerId?: string;
  viewAll: boolean;
  requestingUserId: string;
}) {
  const where: Prisma.RetailerWhereInput = {
    isActive: true,
    ...(params.search && {
      OR: [
        { name: { contains: params.search, mode: 'insensitive' } },
        { phone: { contains: params.search } },
      ],
    }),
    // If the user can't view all retailers, filter to their assignments
    ...(!params.viewAll && {
      salesOfficers: { some: { salesOfficerId: params.requestingUserId } },
    }),
    ...(params.salesOfficerId && {
      salesOfficers: { some: { salesOfficerId: params.salesOfficerId } },
    }),
  };

  const retailers = await prisma.retailer.findMany({
    where,
    orderBy: { createdAt: 'asc' },
    ...buildPrismaPage(params),
  });

  return buildPaginationResult(retailers, params.limit);
}

export async function getRetailerById(id: string) {
  const retailer = await prisma.retailer.findUnique({
    where: { id },
    include: { salesOfficers: { include: { salesOfficer: { select: { id: true, name: true, email: true } } } } },
  });
  if (!retailer) throw AppError.notFound('Retailer');
  return retailer;
}

export async function createRetailer(
  data: {
    name: string;
    phone: string;
    address?: string;
    gstin?: string;
    creditLimit: number;
    isDirectSale: boolean;
    salesOfficerIds?: string[];
  },
  actorId: string
) {
  return prisma.$transaction(async (tx) => {
    const retailer = await tx.retailer.create({
      data: {
        name: data.name,
        phone: data.phone,
        address: data.address,
        gstin: data.gstin,
        creditLimit: data.creditLimit,
        isDirectSale: data.isDirectSale,
      },
    });

    if (data.salesOfficerIds?.length) {
      await tx.retailerSalesOfficer.createMany({
        data: data.salesOfficerIds.map((id) => ({
          retailerId: retailer.id,
          salesOfficerId: id,
        })),
      });
    }

    await writeAuditLog(tx, {
      actorId,
      action: 'create_retailer',
      entityType: 'Retailer',
      entityId: retailer.id,
      diff: data,
    });

    return retailer;
  });
}

export async function updateRetailer(
  id: string,
  data: Partial<{
    name: string;
    phone: string;
    address: string;
    gstin: string;
    creditLimit: number;
    isDirectSale: boolean;
    salesOfficerIds: string[];
  }>,
  actorId: string
) {
  const retailer = await prisma.retailer.findUnique({ where: { id } });
  if (!retailer) throw AppError.notFound('Retailer');

  return prisma.$transaction(async (tx) => {
    const { salesOfficerIds, ...fields } = data;

    const updated = await tx.retailer.update({ where: { id }, data: fields });

    if (salesOfficerIds !== undefined) {
      await tx.retailerSalesOfficer.deleteMany({ where: { retailerId: id } });
      if (salesOfficerIds.length) {
        await tx.retailerSalesOfficer.createMany({
          data: salesOfficerIds.map((soId) => ({
            retailerId: id,
            salesOfficerId: soId,
          })),
        });
      }
    }

    await writeAuditLog(tx, {
      actorId,
      action: 'update_retailer',
      entityType: 'Retailer',
      entityId: id,
      diff: data,
    });

    return updated;
  });
}
