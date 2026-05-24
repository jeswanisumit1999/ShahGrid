import { Router } from 'express';
import * as controller from './retailers.controller';
import { authenticate } from '../../middleware/auth.middleware';
import { requirePermission } from '../../middleware/rbac.middleware';
import { validate } from '../../middleware/validate.middleware';
import { createRetailerSchema, updateRetailerSchema, listRetailersQuerySchema, retailerLedgerQuerySchema } from './retailers.validators';

const router = Router();

router.use(authenticate);

/**
 * @openapi
 * /retailers:
 *   get:
 *     tags: [Retailers]
 *     summary: List retailers (paginated)
 *     description: >
 *       Sales Officers see only retailers assigned to them unless the
 *       `sales_officer_view_all_retailers` app setting is `true`.
 *       Users with `shipments.manage` always see all retailers.
 *     parameters:
 *       - $ref: '#/components/parameters/cursor'
 *       - $ref: '#/components/parameters/limit'
 *       - name: search
 *         in: query
 *         schema: { type: string }
 *         description: Filter by name or phone (case-insensitive)
 *       - name: salesOfficerId
 *         in: query
 *         schema: { type: string, format: uuid }
 *         description: Filter by assigned sales officer
 *     responses:
 *       200:
 *         description: Paginated list of retailers
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data:
 *                   type: array
 *                   items: { $ref: '#/components/schemas/Retailer' }
 *                 pagination: { $ref: '#/components/schemas/PaginationMeta' }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       403:
 *         $ref: '#/components/responses/Forbidden'
 */
router.get('/', requirePermission('retailers', 'read'), validate(listRetailersQuerySchema, 'query'), controller.listRetailers);

/**
 * @openapi
 * /retailers/{id}:
 *   get:
 *     tags: [Retailers]
 *     summary: Get a single retailer with assigned sales officers
 *     parameters:
 *       - $ref: '#/components/parameters/resourceId'
 *     responses:
 *       200:
 *         description: Retailer detail
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data: { $ref: '#/components/schemas/Retailer' }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       404:
 *         $ref: '#/components/responses/NotFound'
 */
router.get('/:id/ledger', requirePermission('retailers', 'read'), validate(retailerLedgerQuerySchema, 'query'), controller.getRetailerLedger);
router.get('/:id', requirePermission('retailers', 'read'), controller.getRetailer);

/**
 * @openapi
 * /retailers:
 *   post:
 *     tags: [Retailers]
 *     summary: Create a new retailer
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema: { $ref: '#/components/schemas/CreateRetailerRequest' }
 *     responses:
 *       201:
 *         description: Retailer created
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data: { $ref: '#/components/schemas/Retailer' }
 *       400:
 *         $ref: '#/components/responses/ValidationError'
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       403:
 *         $ref: '#/components/responses/Forbidden'
 */
router.post('/', requirePermission('retailers', 'manage'), validate(createRetailerSchema), controller.createRetailer);

/**
 * @openapi
 * /retailers/{id}:
 *   patch:
 *     tags: [Retailers]
 *     summary: Update a retailer (partial update)
 *     parameters:
 *       - $ref: '#/components/parameters/resourceId'
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema: { $ref: '#/components/schemas/CreateRetailerRequest' }
 *     responses:
 *       200:
 *         description: Retailer updated
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data: { $ref: '#/components/schemas/Retailer' }
 *       400:
 *         $ref: '#/components/responses/ValidationError'
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       403:
 *         $ref: '#/components/responses/Forbidden'
 *       404:
 *         $ref: '#/components/responses/NotFound'
 */
router.patch('/:id', requirePermission('retailers', 'manage'), validate(updateRetailerSchema), controller.updateRetailer);
router.delete('/:id', requirePermission('retailers', 'manage'), controller.deleteRetailer);

export default router;
