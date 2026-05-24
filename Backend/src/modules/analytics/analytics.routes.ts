import { Router } from 'express';
import * as controller from './analytics.controller';
import { authenticate } from '../../middleware/auth.middleware';
import { requirePermission } from '../../middleware/rbac.middleware';

const router = Router();

router.use(authenticate);

/**
 * @openapi
 * /analytics/dashboard:
 *   get:
 *     tags: [Analytics]
 *     summary: Overall dashboard summary
 *     description: Returns total order count, active retailer count, total pending collection, and the 5 most recent orders.
 *     responses:
 *       200:
 *         description: Dashboard summary
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data:
 *                   type: object
 *                   properties:
 *                     totalOrders: { type: integer, example: 1240 }
 *                     totalRetailers: { type: integer, example: 85 }
 *                     totalPendingCollection: { type: number, example: 342500 }
 *                     recentOrders:
 *                       type: array
 *                       items: { $ref: '#/components/schemas/Order' }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       403:
 *         $ref: '#/components/responses/Forbidden'
 */
router.get('/dashboard', requirePermission('analytics', 'read'), controller.getDashboard);

/**
 * @openapi
 * /analytics/my-stats:
 *   get:
 *     tags: [Analytics]
 *     summary: Performance stats for the currently authenticated sales officer
 *     responses:
 *       200:
 *         description: Personal stats
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data:
 *                   type: object
 *                   properties:
 *                     orderCount: { type: integer, example: 42 }
 *                     visitCount: { type: integer, example: 130 }
 *                     totalPaymentsCollected: { type: number, example: 185000 }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 */
router.get('/my-stats', controller.getMyStats);

/**
 * @openapi
 * /analytics/stock-alerts:
 *   get:
 *     tags: [Analytics]
 *     summary: Products with stock at or below the given threshold
 *     parameters:
 *       - name: threshold
 *         in: query
 *         schema: { type: integer, default: 10 }
 *         description: Alert if stockQuantity ≤ this value
 *     responses:
 *       200:
 *         description: List of low-stock products (max 50)
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data:
 *                   type: array
 *                   items: { $ref: '#/components/schemas/Product' }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       403:
 *         $ref: '#/components/responses/Forbidden'
 */
router.get('/stock-alerts', controller.getStockAlerts);

router.get('/godown-stats', requirePermission('shipments', 'manage'), controller.getGodownStats);

export default router;
