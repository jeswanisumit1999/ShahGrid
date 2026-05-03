import { Router } from 'express';
import * as controller from './visits.controller';
import { authenticate } from '../../middleware/auth.middleware';
import { requirePermission } from '../../middleware/rbac.middleware';
import { validate } from '../../middleware/validate.middleware';
import { createVisitSchema, listVisitsQuerySchema } from './visits.validators';

const router = Router();

router.use(authenticate);

/**
 * @openapi
 * /visits:
 *   get:
 *     tags: [Visits]
 *     summary: List visit logs (paginated, newest first)
 *     parameters:
 *       - $ref: '#/components/parameters/cursor'
 *       - $ref: '#/components/parameters/limit'
 *       - name: retailerId
 *         in: query
 *         schema: { type: string, format: uuid }
 *       - name: userId
 *         in: query
 *         schema: { type: string, format: uuid }
 *     responses:
 *       200:
 *         description: Paginated list of visit logs
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data:
 *                   type: array
 *                   items: { $ref: '#/components/schemas/VisitLog' }
 *                 pagination: { $ref: '#/components/schemas/PaginationMeta' }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       403:
 *         $ref: '#/components/responses/Forbidden'
 */
router.get('/', requirePermission('visits', 'read'), validate(listVisitsQuerySchema, 'query'), controller.listVisits);

/**
 * @openapi
 * /visits:
 *   post:
 *     tags: [Visits]
 *     summary: Log a sales officer's visit to a retailer
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema: { $ref: '#/components/schemas/CreateVisitRequest' }
 *     responses:
 *       201:
 *         description: Visit logged
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data: { $ref: '#/components/schemas/VisitLog' }
 *       400:
 *         $ref: '#/components/responses/ValidationError'
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       403:
 *         $ref: '#/components/responses/Forbidden'
 */
router.post('/', requirePermission('visits', 'create'), validate(createVisitSchema), controller.logVisit);

export default router;
