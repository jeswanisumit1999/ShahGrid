import { Router } from 'express';
import * as controller from './shipments.controller';
import { authenticate } from '../../middleware/auth.middleware';
import { requirePermission } from '../../middleware/rbac.middleware';
import { validate } from '../../middleware/validate.middleware';
import { updateShipmentStatusSchema, listShipmentsQuerySchema, splitShipmentSchema } from './shipments.validators';

const router = Router();

router.use(authenticate);

/**
 * @openapi
 * /shipments:
 *   get:
 *     tags: [Shipments]
 *     summary: List shipments (paginated)
 *     parameters:
 *       - $ref: '#/components/parameters/cursor'
 *       - $ref: '#/components/parameters/limit'
 *       - name: orderId
 *         in: query
 *         schema: { type: string, format: uuid }
 *       - name: companyId
 *         in: query
 *         schema: { type: string, format: uuid }
 *       - name: status
 *         in: query
 *         schema:
 *           type: string
 *           enum:
 *             - Pending Stock Verification
 *             - Pending Stock Availability
 *             - Stock Confirmed
 *             - Dispatched
 *             - Delivered
 *             - Cancelled
 *     responses:
 *       200:
 *         description: Paginated list of shipments
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data:
 *                   type: array
 *                   items: { $ref: '#/components/schemas/Shipment' }
 *                 pagination: { $ref: '#/components/schemas/PaginationMeta' }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       403:
 *         $ref: '#/components/responses/Forbidden'
 */
router.get('/', requirePermission('shipments', 'manage'), validate(listShipmentsQuerySchema, 'query'), controller.listShipments);

/**
 * @openapi
 * /shipments/{id}:
 *   get:
 *     tags: [Shipments]
 *     summary: Get a shipment with its items and linked order
 *     parameters:
 *       - $ref: '#/components/parameters/resourceId'
 *     responses:
 *       200:
 *         description: Shipment detail
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data: { $ref: '#/components/schemas/Shipment' }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       404:
 *         $ref: '#/components/responses/NotFound'
 */
router.get('/:id', requirePermission('shipments', 'manage'), controller.getShipment);

/**
 * @openapi
 * /shipments/{id}/status:
 *   patch:
 *     tags: [Shipments]
 *     summary: Advance a shipment through its lifecycle
 *     description: >
 *       Allowed transitions are role-gated (not just permission-gated):
 *
 *       | From | To | Allowed roles |
 *       |---|---|---|
 *       | Pending Stock Verification | Stock Confirmed | Supply Chain, Admin |
 *       | Pending Stock Availability | Stock Confirmed | Supply Chain, Admin |
 *       | Stock Confirmed | Dispatched | Supply Chain, Godown Manager, Admin |
 *       | Dispatched | Delivered | Godown Manager, Admin |
 *
 *       Stock is deducted from inventory only when the shipment reaches **Delivered**.
 *     parameters:
 *       - $ref: '#/components/parameters/resourceId'
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema: { $ref: '#/components/schemas/UpdateShipmentStatusRequest' }
 *     responses:
 *       200:
 *         description: Status updated
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data: { $ref: '#/components/schemas/Shipment' }
 *       400:
 *         description: Invalid status transition for the user's role
 *         content:
 *           application/json:
 *             schema: { $ref: '#/components/schemas/ErrorResponse' }
 *             example:
 *               success: false
 *               error:
 *                 code: INVALID_STATUS_TRANSITION
 *                 message: 'Transition from "Dispatched" to "Stock Confirmed" is not allowed for your role'
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       404:
 *         $ref: '#/components/responses/NotFound'
 */
router.patch('/:id/status', requirePermission('shipments', 'manage'), validate(updateShipmentStatusSchema), controller.updateStatus);
router.post('/:id/split', requirePermission('shipments', 'manage'), validate(splitShipmentSchema), controller.splitShipment);

export default router;
