import { Request, Response, NextFunction } from 'express';
import * as returnsService from './returns.service';
import { sendSuccess } from '../../utils/response';

export async function createReturn(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await returnsService.createReturn(req.body, req.user!.id);
    sendSuccess(res, result, 201);
  } catch (err) { next(err); }
}

export async function listReturns(req: Request, res: Response, next: NextFunction) {
  try {
    const { cursor, limit, orderId, retailerId } = req.query as any;
    const result = await returnsService.listReturns({ cursor, limit: Number(limit) || 20, orderId, retailerId });
    sendSuccess(res, result.items, 200, { nextCursor: result.nextCursor, hasMore: result.hasMore });
  } catch (err) { next(err); }
}
