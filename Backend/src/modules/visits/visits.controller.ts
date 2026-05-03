import { Request, Response, NextFunction } from 'express';
import * as visitsService from './visits.service';
import { sendSuccess } from '../../utils/response';

export async function logVisit(req: Request, res: Response, next: NextFunction) {
  try {
    const visit = await visitsService.logVisit({ ...req.body, userId: req.user!.id });
    sendSuccess(res, visit, 201);
  } catch (err) { next(err); }
}

export async function listVisits(req: Request, res: Response, next: NextFunction) {
  try {
    const { cursor, limit, retailerId, userId } = req.query as any;
    const result = await visitsService.listVisits({ cursor, limit: Number(limit) || 20, retailerId, userId });
    sendSuccess(res, result.items, 200, { nextCursor: result.nextCursor, hasMore: result.hasMore });
  } catch (err) { next(err); }
}
