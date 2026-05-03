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
