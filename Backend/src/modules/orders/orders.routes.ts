import { Router } from 'express';
import * as controller from './orders.controller';
import { authenticate } from '../../middleware/auth.middleware';
import { requirePermission } from '../../middleware/rbac.middleware';
import { validate } from '../../middleware/validate.middleware';
import { createOrderSchema, listOrdersQuerySchema, updateOrderItemSchema, addOrderItemSchema, updateOrderSchema } from './orders.validators';

const router = Router();

router.use(authenticate);

/**
 * @openapi
 * /orders:
 *   get:
 *     tags: [Orders]
 *     summary: List orders (paginated, newest first)
 *     parameters:
 *       - $ref: '#/components/parameters/cursor'
 *       - $ref: '#/components/parameters/limit'
 *       - name: retailerId
 *         in: query
 *         schema: { type: string, format: uuid }
 *         description: Filter by retailer
 *       - name: salesOfficerId
 *         in: query
 *         schema: { type: string, format: uuid }
 *         description: Filter by sales officer
 *     responses:
 *       200:
 *         description: Paginated list of orders
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data:
 *                   type: array
 *                   items: { $ref: '#/components/schemas/Order' }
 *                 pagination: { $ref: '#/components/schemas/PaginationMeta' }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       403:
 *         $ref: '#/components/responses/Forbidden'
 */
router.get('/', requirePermission('orders', 'read'), validate(listOrdersQuerySchema, 'query'), controller.listOrders);

/**
 * @openapi
 * /orders/{id}:
 *   get:
 *     tags: [Orders]
 *     summary: Get a single order with full details (items, shipments, payments)
 *     parameters:
 *       - $ref: '#/components/parameters/resourceId'
 *     responses:
 *       200:
 *         description: Order detail
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data: { $ref: '#/components/schemas/Order' }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       404:
 *         $ref: '#/components/responses/NotFound'
 */
router.get('/:id', requirePermission('orders', 'read'), controller.getOrder);

/**
 * @openapi
 * /orders:
 *   post:
 *     tags: [Orders]
 *     summary: Place a new order
 *     description: >
 *       Creates the order and automatically generates shipments based on stock availability.
 *       If the retailer's `isDirectSale` flag is true, stock is deducted immediately
 *       and no shipment lifecycle is created.
 *
 *       **Credit limit check:** the order is rejected if
 *       `retailer.pendingCollection + orderTotal > retailer.creditLimit`
 *       unless the `allow_credit_override` app setting is `true`.
 *
 *       **Stock split logic:** items with sufficient stock go into a
 *       "Pending Stock Verification" shipment; items without stock go into
 *       "Pending Stock Availability".
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema: { $ref: '#/components/schemas/CreateOrderRequest' }
 *           example:
 *             retailerId: "550e8400-e29b-41d4-a716-446655440001"
 *             salesOfficerId: "550e8400-e29b-41d4-a716-446655440002"
 *             notes: "Urgent delivery needed before Diwali"
 *             items:
 *               - productId: "550e8400-e29b-41d4-a716-446655440010"
 *                 quantity: 10
 *                 unitPrice: 45.00
 *               - productId: "550e8400-e29b-41d4-a716-446655440011"
 *                 quantity: 5
 *                 unitPrice: 120.00
 *     responses:
 *       201:
 *         description: Order created with shipments
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data: { $ref: '#/components/schemas/Order' }
 *       400:
 *         description: Credit limit exceeded or insufficient stock (direct-sale only)
 *         content:
 *           application/json:
 *             schema: { $ref: '#/components/schemas/ErrorResponse' }
 *             example:
 *               success: false
 *               error:
 *                 code: CREDIT_LIMIT_EXCEEDED
 *                 message: "Order exceeds retailer credit limit. Limit: 50000, current pending: 45000, order total: 10000"
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       403:
 *         $ref: '#/components/responses/Forbidden'
 */
router.post('/', requirePermission('orders', 'create'), validate(createOrderSchema), controller.createOrder);

router.patch('/:id', requirePermission('orders', 'manage'), validate(updateOrderSchema), controller.updateOrder);
router.post('/:id/items', requirePermission('orders', 'manage'), validate(addOrderItemSchema), controller.addOrderItem);
router.patch('/:id/items/:itemId', requirePermission('orders', 'manage'), validate(updateOrderItemSchema), controller.updateOrderItem);

export default router;
