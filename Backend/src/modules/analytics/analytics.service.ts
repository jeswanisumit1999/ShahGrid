import { prisma } from '../../lib/prisma';

export async function getDashboardSummary() {
  const [totalOrders, totalRetailers, totalPendingCollection, recentOrders] = await Promise.all([
    prisma.order.count(),
    prisma.retailer.count({ where: { isActive: true } }),
    prisma.retailer.aggregate({ _sum: { pendingCollection: true } }),
    prisma.order.findMany({
      take: 5,
      orderBy: { createdAt: 'desc' },
      include: {
        retailer: { select: { id: true, name: true } },
        salesOfficer: { select: { id: true, name: true } },
      },
    }),
  ]);

  return {
    totalOrders,
    totalRetailers,
    totalPendingCollection: totalPendingCollection._sum.pendingCollection ?? 0,
    recentOrders,
  };
}

export async function getSalesOfficerStats(salesOfficerId: string) {
  const [orderCount, visitCount, paymentSum, outstandingSum] = await Promise.all([
    prisma.order.count({ where: { salesOfficerId } }),
    prisma.checkIn.count({ where: { userId: salesOfficerId } }),
    prisma.payment.aggregate({
      where: { order: { salesOfficerId } },
      _sum: { amount: true },
    }),
    prisma.retailer.aggregate({
      where: { salesOfficers: { some: { salesOfficerId } } },
      _sum: { pendingCollection: true },
    }),
  ]);

  return {
    orderCount,
    visitCount,
    totalPaymentsCollected: paymentSum._sum.amount ?? 0,
    totalOutstanding: outstandingSum._sum.pendingCollection ?? 0,
  };
}

export async function getStockAlerts() {
  const products = await prisma.product.findMany({
    where: { isActive: true, lowStockThreshold: { not: null } },
    orderBy: { stockQuantity: 'asc' },
    include: { company: { select: { id: true, name: true } } },
  });
  return products.filter((p) => p.stockQuantity <= p.lowStockThreshold!).slice(0, 50);
}

export async function getCollectionSummary() {
  const officers = await prisma.user.findMany({
    where: {
      isActive: true,
      userRoles: { some: { role: { name: 'Sales Officer' } } },
    },
    select: {
      id: true,
      name: true,
      email: true,
      avatarUrl: true,
      assignedRetailers: {
        where: { retailer: { isActive: true } },
        select: {
          retailer: {
            select: { id: true, name: true, phone: true, pendingCollection: true },
          },
        },
      },
    },
    orderBy: { name: 'asc' },
  });

  return officers.map((officer) => {
    const retailers = officer.assignedRetailers.map((r) => ({
      id: r.retailer.id,
      name: r.retailer.name,
      phone: r.retailer.phone,
      pendingCollection: Number(r.retailer.pendingCollection),
    }));
    const totalPending = retailers.reduce((sum, r) => sum + r.pendingCollection, 0);
    return {
      salesOfficer: {
        id: officer.id,
        name: officer.name,
        email: officer.email,
        avatarUrl: officer.avatarUrl,
      },
      totalPending,
      retailers,
    };
  });
}

export async function getGodownStats() {
  const [pendingAvailability, pendingVerification, readyForDispatch] = await Promise.all([
    prisma.shipment.count({ where: { status: 'Pending Stock Availability' } }),
    prisma.shipment.count({ where: { status: 'Pending Stock Verification' } }),
    prisma.shipment.count({ where: { status: 'Ready for Dispatch' } }),
  ]);

  return { pendingAvailability, pendingVerification, readyForDispatch };
}
