import { Router } from 'express';
import * as controller from './settings.controller';
import { authenticate } from '../../middleware/auth.middleware';
import { requirePermission } from '../../middleware/rbac.middleware';
import { validate } from '../../middleware/validate.middleware';
import { updateSettingSchema } from './settings.validators';

const router = Router();

router.use(authenticate, requirePermission('settings', 'manage'));

/**
 * @openapi
 * /settings:
 *   get:
 *     tags: [Settings]
 *     summary: List all app settings
 *     description: >
 *       Available settings:
 *       - `allow_credit_override` — allow orders beyond retailer credit limit
 *       - `sales_officer_view_all_retailers` — whether sales officers can view all retailers
 *       - `sales_officer_order_all_retailers` — whether sales officers can order for any retailer
 *     responses:
 *       200:
 *         description: All app settings
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data:
 *                   type: array
 *                   items: { $ref: '#/components/schemas/AppSetting' }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       403:
 *         $ref: '#/components/responses/Forbidden'
 */
router.get('/', controller.listSettings);

/**
 * @openapi
 * /settings/{key}:
 *   patch:
 *     tags: [Settings]
 *     summary: Update an app setting by its key
 *     parameters:
 *       - name: key
 *         in: path
 *         required: true
 *         schema: { type: string }
 *         example: allow_credit_override
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema: { $ref: '#/components/schemas/UpdateSettingRequest' }
 *     responses:
 *       200:
 *         description: Setting updated
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data: { $ref: '#/components/schemas/AppSetting' }
 *       400:
 *         $ref: '#/components/responses/ValidationError'
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       403:
 *         $ref: '#/components/responses/Forbidden'
 *       404:
 *         $ref: '#/components/responses/NotFound'
 */
router.patch('/:key', validate(updateSettingSchema), controller.updateSetting);

export default router;
