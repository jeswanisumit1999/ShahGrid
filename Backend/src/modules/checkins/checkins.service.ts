import { Prisma } from '@prisma/client';
import { prisma } from '../../lib/prisma';
import { buildPrismaPage, buildPaginationResult } from '../../utils/pagination';

export async function createCheckIn(input: {
  userId: string;
  latitude: number;
  longitude: number;
  notes?: string;
}) {
  return prisma.checkIn.create({
    data: {
      userId: input.userId,
      latitude: input.latitude,
      longitude: input.longitude,
      notes: input.notes,
    },
    include: { user: { select: { id: true, name: true } } },
  });
}

export async function listCheckIns(params: {
  cursor?: string;
  limit: number;
  userId?: string;
}) {
  const where: Prisma.CheckInWhereInput = {
    ...(params.userId && { userId: params.userId }),
  };

  const items = await prisma.checkIn.findMany({
    where,
    orderBy: { checkedInAt: 'desc' },
    ...buildPrismaPage(params),
    include: { user: { select: { id: true, name: true } } },
  });

  return buildPaginationResult(items, params.limit);
}
