import { z } from 'zod';

export const assignRoleSchema = z.object({
  userId: z.string().uuid(),
  roleId: z.string().uuid(),
});

export const listUsersQuerySchema = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  search: z.string().optional(),
});

export const createRoleSchema = z.object({
  name: z.string().min(1).max(64),
  description: z.string().max(255).optional(),
  permissionIds: z.array(z.string().uuid()).default([]),
});

export const updateRolePermissionsSchema = z.object({
  permissionIds: z.array(z.string().uuid()),
});
