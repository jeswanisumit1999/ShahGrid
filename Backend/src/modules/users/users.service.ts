import { prisma } from '../../lib/prisma';
import { AppError } from '../../errors/AppError';
import { buildPrismaPage, buildPaginationResult } from '../../utils/pagination';
import { writeAuditLog } from '../../utils/audit';

export async function listUsers(params: { cursor?: string; limit: number; search?: string }) {
  const where = params.search
    ? {
        OR: [
          { name: { contains: params.search, mode: 'insensitive' as const } },
          { email: { contains: params.search, mode: 'insensitive' as const } },
        ],
      }
    : {};

  const users = await prisma.user.findMany({
    where,
    orderBy: { createdAt: 'asc' },
    ...buildPrismaPage(params),
    include: { userRoles: { include: { role: true } } },
  });

  return buildPaginationResult(users, params.limit);
}

export async function getUserById(id: string) {
  const user = await prisma.user.findUnique({
    where: { id },
    include: {
      userRoles: {
        include: { role: { include: { rolePermissions: { include: { permission: true } } } } },
      },
    },
  });
  if (!user) throw AppError.notFound('User');
  return user;
}

export async function assignRole(params: {
  userId: string;
  roleId: string;
  actorId: string;
}) {
  const [user, role] = await Promise.all([
    prisma.user.findUnique({ where: { id: params.userId } }),
    prisma.role.findUnique({ where: { id: params.roleId } }),
  ]);

  if (!user) throw AppError.notFound('User');
  if (!role) throw AppError.notFound('Role');

  await prisma.$transaction(async (tx) => {
    // Remove all existing roles before assigning new one
    await tx.userRole.deleteMany({ where: { userId: params.userId } });
    await tx.userRole.create({
      data: { userId: params.userId, roleId: params.roleId, assignedBy: params.actorId },
    });
    await writeAuditLog(tx, {
      actorId: params.actorId,
      action: 'assign_role',
      entityType: 'User',
      entityId: params.userId,
      diff: { roleId: params.roleId, roleName: role.name },
    });
  });
}

export async function deactivateUser(userId: string, actorId: string) {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) throw AppError.notFound('User');

  await prisma.$transaction(async (tx) => {
    await tx.user.update({ where: { id: userId }, data: { isActive: false } });
    await writeAuditLog(tx, {
      actorId,
      action: 'deactivate_user',
      entityType: 'User',
      entityId: userId,
    });
  });
}

export async function listRoles() {
  return prisma.role.findMany({
    include: { rolePermissions: { include: { permission: true } } },
    orderBy: { name: 'asc' },
  });
}

export async function listPermissions() {
  return prisma.permission.findMany({ orderBy: [{ resource: 'asc' }, { action: 'asc' }] });
}

export async function createRole(input: {
  name: string;
  description?: string;
  permissionIds: string[];
  actorId: string;
}) {
  const existing = await prisma.role.findUnique({ where: { name: input.name } });
  if (existing) throw AppError.conflict(`Role "${input.name}" already exists`);

  return prisma.$transaction(async (tx) => {
    const role = await tx.role.create({
      data: {
        name: input.name,
        description: input.description,
        rolePermissions: {
          create: input.permissionIds.map((permissionId) => ({ permissionId })),
        },
      },
      include: { rolePermissions: { include: { permission: true } } },
    });
    await writeAuditLog(tx, {
      actorId: input.actorId,
      action: 'create_role',
      entityType: 'Role',
      entityId: role.id,
      diff: { name: role.name, permissionCount: input.permissionIds.length },
    });
    return role;
  });
}

export async function updateRolePermissions(
  roleId: string,
  permissionIds: string[],
  actorId: string
) {
  const role = await prisma.role.findUnique({ where: { id: roleId } });
  if (!role) throw AppError.notFound('Role');

  return prisma.$transaction(async (tx) => {
    await tx.rolePermission.deleteMany({ where: { roleId } });
    if (permissionIds.length > 0) {
      await tx.rolePermission.createMany({
        data: permissionIds.map((permissionId) => ({ roleId, permissionId })),
        skipDuplicates: true,
      });
    }
    await writeAuditLog(tx, {
      actorId,
      action: 'update_role_permissions',
      entityType: 'Role',
      entityId: roleId,
      diff: { roleName: role.name, permissionCount: permissionIds.length },
    });
    return prisma.role.findUnique({
      where: { id: roleId },
      include: { rolePermissions: { include: { permission: true } } },
    });
  });
}

export async function deleteRole(roleId: string, actorId: string) {
  const role = await prisma.role.findUnique({ where: { id: roleId } });
  if (!role) throw AppError.notFound('Role');
  if (role.isSystemRole) throw AppError.badRequest('System roles cannot be deleted', 'SYSTEM_ROLE');

  const usersWithRole = await prisma.userRole.count({ where: { roleId } });
  if (usersWithRole > 0)
    throw AppError.badRequest(
      `Cannot delete role assigned to ${usersWithRole} user(s)`,
      'ROLE_IN_USE'
    );

  await prisma.$transaction(async (tx) => {
    await tx.rolePermission.deleteMany({ where: { roleId } });
    await tx.role.delete({ where: { id: roleId } });
    await writeAuditLog(tx, {
      actorId,
      action: 'delete_role',
      entityType: 'Role',
      entityId: roleId,
      diff: { name: role.name },
    });
  });
}

export async function listActivityLog(params: {
  cursor?: string;
  limit: number;
  search?: string;
}) {
  const { cursor, limit, search } = params;

  // Find actor IDs matching name search
  let actorIdFilter: string[] | undefined;
  if (search) {
    const matchingActors = await prisma.user.findMany({
      where: { name: { contains: search, mode: 'insensitive' } },
      select: { id: true },
    });
    if (matchingActors.length > 0) {
      actorIdFilter = matchingActors.map((a) => a.id);
    }
  }

  const where: {
    createdAt?: { lt: Date };
    OR?: object[];
  } = cursor ? { createdAt: { lt: new Date(cursor) } } : {};

  if (search) {
    const orConditions: object[] = [
      { action: { contains: search, mode: 'insensitive' } },
      { entityType: { contains: search, mode: 'insensitive' } },
    ];
    if (actorIdFilter && actorIdFilter.length > 0) {
      orConditions.push({ actorId: { in: actorIdFilter } });
    }
    where.OR = orConditions;
  }

  const logs = await prisma.auditLog.findMany({
    where,
    take: limit + 1,
    orderBy: { createdAt: 'desc' },
  });

  const hasMore = logs.length > limit;
  if (hasMore) logs.pop();

  // Batch-fetch actor names
  const actorIds = [...new Set(logs.map((l) => l.actorId))];
  const actors = actorIds.length > 0
    ? await prisma.user.findMany({
        where: { id: { in: actorIds } },
        select: { id: true, name: true, email: true },
      })
    : [];
  const actorMap = Object.fromEntries(actors.map((a) => [a.id, a]));

  // Batch-fetch entity labels grouped by entityType
  const byType = new Map<string, string[]>();
  for (const log of logs) {
    const arr = byType.get(log.entityType) ?? [];
    arr.push(log.entityId);
    byType.set(log.entityType, arr);
  }

  const entityLabelMap = new Map<string, string>(); // entityId -> human label

  await Promise.all(
    [...byType.entries()].map(async ([type, rawIds]) => {
      const ids = [...new Set(rawIds)];
      switch (type) {
        case 'Order': {
          const rows = await prisma.order.findMany({
            where: { id: { in: ids } },
            select: { id: true, retailer: { select: { name: true } } },
          });
          for (const r of rows) entityLabelMap.set(r.id, r.retailer.name);
          break;
        }
        case 'Payment': {
          const rows = await prisma.payment.findMany({
            where: { id: { in: ids } },
            select: { id: true, retailer: { select: { name: true } } },
          });
          for (const r of rows) entityLabelMap.set(r.id, r.retailer.name);
          break;
        }
        case 'User': {
          const rows = await prisma.user.findMany({
            where: { id: { in: ids } },
            select: { id: true, name: true },
          });
          for (const r of rows) entityLabelMap.set(r.id, r.name);
          break;
        }
        case 'Role': {
          const rows = await prisma.role.findMany({
            where: { id: { in: ids } },
            select: { id: true, name: true },
          });
          for (const r of rows) entityLabelMap.set(r.id, r.name);
          break;
        }
        case 'Retailer': {
          const rows = await prisma.retailer.findMany({
            where: { id: { in: ids } },
            select: { id: true, name: true },
          });
          for (const r of rows) entityLabelMap.set(r.id, r.name);
          break;
        }
        case 'Product': {
          const rows = await prisma.product.findMany({
            where: { id: { in: ids } },
            select: { id: true, name: true },
          });
          for (const r of rows) entityLabelMap.set(r.id, r.name);
          break;
        }
        case 'Shipment': {
          const rows = await prisma.shipment.findMany({
            where: { id: { in: ids } },
            select: { id: true, order: { select: { retailer: { select: { name: true } } } } },
          });
          for (const r of rows) entityLabelMap.set(r.id, r.order.retailer.name);
          break;
        }
      }
    })
  );

  const items = logs.map((log) => {
    // DB lookup first; fall back to diff fields for deleted entities
    let entityLabel: string | null = entityLabelMap.get(log.entityId) ?? null;
    if (!entityLabel && log.diff) {
      const d = log.diff as Record<string, unknown>;
      entityLabel = (d['name'] ?? d['roleName'] ?? d['userName'] ?? null) as string | null;
    }
    return {
      id: log.id,
      actorId: log.actorId,
      actorName: actorMap[log.actorId]?.name ?? 'Unknown',
      actorEmail: actorMap[log.actorId]?.email ?? '',
      action: log.action,
      entityType: log.entityType,
      entityId: log.entityId,
      entityLabel,
      diff: log.diff,
      createdAt: log.createdAt.toISOString(),
    };
  });

  return {
    items,
    hasMore,
    nextCursor: hasMore && items.length > 0 ? items[items.length - 1].createdAt : null,
  };
}
