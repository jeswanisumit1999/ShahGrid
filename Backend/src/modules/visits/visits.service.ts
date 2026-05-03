import { Prisma } from '@prisma/client';
import { prisma } from '../../lib/prisma';
import { AppError } from '../../errors/AppError';
import { buildPrismaPage, buildPaginationResult } from '../../utils/pagination';

export async function logVisit(input: {
  retailerId: string;
  latitude: number;
  longitude: number;
  notes?: string;
  userId: string;
}) {
  const retailer = await prisma.retailer.findUnique({ where: { id: input.retailerId } });
  if (!retailer) throw AppError.notFound('Retailer');

  return prisma.visitLog.create({
    data: {
      userId: input.userId,
      retailerId: input.retailerId,
      latitude: input.latitude,
      longitude: input.longitude,
      notes: input.notes,
    },
  });
}

export async function listVisits(params: {
  cursor?: string;
  limit: number;
  retailerId?: string;
  userId?: string;
}) {
  const where: Prisma.VisitLogWhereInput = {
    ...(params.retailerId && { retailerId: params.retailerId }),
    ...(params.userId && { userId: params.userId }),
  };

  const visits = await prisma.visitLog.findMany({
    where,
    orderBy: { visitedAt: 'desc' },
    ...buildPrismaPage(params),
    include: {
      user: { select: { id: true, name: true } },
      retailer: { select: { id: true, name: true } },
    },
  });

  return buildPaginationResult(visits, params.limit);
}
