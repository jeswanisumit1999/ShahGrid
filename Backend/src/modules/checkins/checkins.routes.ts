import { Router } from 'express';
import * as controller from './checkins.controller';
import { authenticate } from '../../middleware/auth.middleware';
import { requirePermission } from '../../middleware/rbac.middleware';
import { validate } from '../../middleware/validate.middleware';
import { createCheckInSchema, listCheckInsQuerySchema } from './checkins.validators';

const router = Router();
router.use(authenticate);

router.get('/', requirePermission('checkins', 'read'), validate(listCheckInsQuerySchema, 'query'), controller.listCheckIns);
router.post('/', requirePermission('checkins', 'create'), validate(createCheckInSchema), controller.createCheckIn);

export default router;
