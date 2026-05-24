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
  const [orderCount, visitCount, paymentSum] = await Promise.all([
    prisma.order.count({ where: { salesOfficerId } }),
    prisma.visitLog.count({ where: { userId: salesOfficerId } }),
    prisma.payment.aggregate({
      where: { order: { salesOfficerId } },
      _sum: { amount: true },
    }),
  ]);

  return {
    orderCount,
    visitCount,
    totalPaymentsCollected: paymentSum._sum.amount ?? 0,
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

export async function getGodownStats() {
  const [pendingAvailability, pendingVerification, readyForDispatch] = await Promise.all([
    prisma.shipment.count({ where: { status: 'Pending Stock Availability' } }),
    prisma.shipment.count({ where: { status: 'Pending Stock Verification' } }),
    prisma.shipment.count({ where: { status: 'Ready for Dispatch' } }),
  ]);

  return { pendingAvailability, pendingVerification, readyForDispatch };
}
