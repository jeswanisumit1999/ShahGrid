import { Request, Response, NextFunction } from 'express';
import * as service from './checkins.service';
import { sendSuccess } from '../../utils/response';

export async function createCheckIn(req: Request, res: Response, next: NextFunction) {
  try {
    const checkIn = await service.createCheckIn({
      userId: req.user!.id,
      latitude: req.body.latitude,
      longitude: req.body.longitude,
      notes: req.body.notes,
    });
    sendSuccess(res, checkIn, 201);
  } catch (err) {
    next(err);
  }
}

export async function listCheckIns(req: Request, res: Response, next: NextFunction) {
  try {
    const canViewAll = req.user!.roles.includes('Admin') || req.user!.roles.includes('Supply Chain');
    const userId = canViewAll
      ? (req.query.userId as string | undefined)
      : req.user!.id;

    const result = await service.listCheckIns({
      cursor: req.query.cursor as string | undefined,
      limit: Number(req.query.limit) || 20,
      userId,
    });
    sendSuccess(res, result.items, 200, { nextCursor: result.nextCursor, hasMore: result.hasMore });
  } catch (err) {
    next(err);
  }
}
