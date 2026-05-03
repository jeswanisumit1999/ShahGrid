import { Router } from 'express';
import * as controller from './returns.controller';
import { authenticate } from '../../middleware/auth.middleware';
import { requirePermission } from '../../middleware/rbac.middleware';
import { validate } from '../../middleware/validate.middleware';
import { createReturnSchema, listReturnsQuerySchema } from './returns.validators';

const router = Router();

router.use(authenticate);

/**
 * @openapi
 * /returns:
 *   get:
 *     tags: [Returns]
 *     summary: List returns (paginated)
 *     parameters:
 *       - $ref: '#/components/parameters/cursor'
 *       - $ref: '#/components/parameters/limit'
 *       - name: orderId
 *         in: query
 *         schema: { type: string, format: uuid }
 *       - name: retailerId
 *         in: query
 *         schema: { type: string, format: uuid }
 *     responses:
 *       200:
 *         description: Paginated list of returns
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data:
 *                   type: array
 *                   items: { $ref: '#/components/schemas/Return' }
 *                 pagination: { $ref: '#/components/schemas/PaginationMeta' }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       403:
 *         $ref: '#/components/responses/Forbidden'
 */
router.get('/', requirePermission('returns', 'manage'), validate(listReturnsQuerySchema, 'query'), controller.listReturns);

/**
 * @openapi
 * /returns:
 *   post:
 *     tags: [Returns]
 *     summary: Submit a product return
 *     description: >
 *       Validates that returned quantities don't exceed delivered quantities,
 *       restores stock for returned items, and decrements the retailer's
 *       `pendingCollection` by the computed return value (quantity × unit price).
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema: { $ref: '#/components/schemas/CreateReturnRequest' }
 *     responses:
 *       201:
 *         description: Return created, stock restored
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data: { $ref: '#/components/schemas/Return' }
 *       400:
 *         description: Return quantity exceeds delivered quantity
 *         content:
 *           application/json:
 *             schema: { $ref: '#/components/schemas/ErrorResponse' }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       403:
 *         $ref: '#/components/responses/Forbidden'
 */
router.post('/', requirePermission('returns', 'manage'), validate(createReturnSchema), controller.createReturn);

export default router;
