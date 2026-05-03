import { Router } from 'express';
import * as controller from './users.controller';
import { authenticate } from '../../middleware/auth.middleware';
import { requirePermission } from '../../middleware/rbac.middleware';
import { validate } from '../../middleware/validate.middleware';
import { assignRoleSchema, listUsersQuerySchema, createRoleSchema, updateRolePermissionsSchema } from './users.validators';

const router = Router();

router.use(authenticate);

/**
 * @openapi
 * /users:
 *   get:
 *     tags: [Users]
 *     summary: List all users (paginated)
 *     parameters:
 *       - $ref: '#/components/parameters/cursor'
 *       - $ref: '#/components/parameters/limit'
 *       - name: search
 *         in: query
 *         schema: { type: string }
 *         description: Filter by name or email (case-insensitive)
 *     responses:
 *       200:
 *         description: Paginated list of users
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data:
 *                   type: array
 *                   items: { $ref: '#/components/schemas/UserDetail' }
 *                 pagination: { $ref: '#/components/schemas/PaginationMeta' }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       403:
 *         $ref: '#/components/responses/Forbidden'
 */
router.get('/', requirePermission('users', 'read'), validate(listUsersQuerySchema, 'query'), controller.listUsers);

/**
 * @openapi
 * /users/roles:
 *   get:
 *     tags: [Users]
 *     summary: List all system roles with their permissions
 *     responses:
 *       200:
 *         description: Array of roles
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data:
 *                   type: array
 *                   items: { $ref: '#/components/schemas/Role' }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       403:
 *         $ref: '#/components/responses/Forbidden'
 */
router.get('/roles', requirePermission('roles', 'manage'), controller.listRoles);
router.post('/roles', requirePermission('roles', 'manage'), validate(createRoleSchema), controller.createRole);
router.patch('/roles/:roleId/permissions', requirePermission('roles', 'manage'), validate(updateRolePermissionsSchema), controller.updateRolePermissions);
router.delete('/roles/:roleId', requirePermission('roles', 'manage'), controller.deleteRole);
router.get('/permissions', requirePermission('roles', 'manage'), controller.listPermissions);

/**
 * @openapi
 * /users/{id}:
 *   get:
 *     tags: [Users]
 *     summary: Get a single user with their roles and permissions
 *     parameters:
 *       - $ref: '#/components/parameters/resourceId'
 *     responses:
 *       200:
 *         description: User detail
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data: { $ref: '#/components/schemas/UserDetail' }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       404:
 *         $ref: '#/components/responses/NotFound'
 */
router.get('/:id', requirePermission('users', 'read'), controller.getUser);

/**
 * @openapi
 * /users/assign-role:
 *   post:
 *     tags: [Users]
 *     summary: Assign a role to a user (replaces any existing role)
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema: { $ref: '#/components/schemas/AssignRoleRequest' }
 *     responses:
 *       200:
 *         description: Role assigned
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       403:
 *         $ref: '#/components/responses/Forbidden'
 *       404:
 *         $ref: '#/components/responses/NotFound'
 */
router.post('/assign-role', requirePermission('roles', 'manage'), validate(assignRoleSchema), controller.assignRole);

/**
 * @openapi
 * /users/{id}/deactivate:
 *   patch:
 *     tags: [Users]
 *     summary: Deactivate a user account (blocks login)
 *     parameters:
 *       - $ref: '#/components/parameters/resourceId'
 *     responses:
 *       200:
 *         description: User deactivated
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       403:
 *         $ref: '#/components/responses/Forbidden'
 *       404:
 *         $ref: '#/components/responses/NotFound'
 */
router.patch('/:id/deactivate', requirePermission('users', 'manage'), controller.deactivateUser);

export default router;
