import { Router } from 'express';
import { authenticate } from '../../middleware/auth.middleware';
import { requirePermission } from '../../middleware/rbac.middleware';
import { getChallan } from './challans.controller';

const router = Router();

router.use(authenticate);

router.get('/:id/challan', requirePermission('challans', 'generate'), getChallan);

export default router;
