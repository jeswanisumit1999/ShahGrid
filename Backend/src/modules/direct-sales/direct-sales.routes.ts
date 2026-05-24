import { Router } from 'express';
import * as controller from './direct-sales.controller';
import { authenticate } from '../../middleware/auth.middleware';
import { requirePermission } from '../../middleware/rbac.middleware';
import { validate } from '../../middleware/validate.middleware';
import { createDirectSaleSchema, listDirectSalesQuerySchema } from './direct-sales.validators';

const router = Router();

router.use(authenticate, requirePermission('orders', 'direct_sale'));

router.get('/', validate(listDirectSalesQuerySchema, 'query'), controller.listDirectSales);
router.post('/', validate(createDirectSaleSchema), controller.createDirectSale);
router.get('/:id', controller.getDirectSale);
router.get('/:id/challan', controller.getDirectSaleChallan);

export default router;
