import { Request, Response, NextFunction } from 'express';
import * as paymentsService from './payments.service';
import { sendSuccess } from '../../utils/response';

export async function recordPayment(req: Request, res: Response, next: NextFunction) {
  try {
    const payment = await paymentsService.recordPayment(req.body, req.user!.id);
    sendSuccess(res, payment, 201);
  } catch (err) { next(err); }
}

export async function listPayments(req: Request, res: Response, next: NextFunction) {
  try {
    const { cursor, limit, orderId, retailerId } = req.query as any;
    const result = await paymentsService.listPayments({ cursor, limit: Number(limit) || 20, orderId, retailerId });
    sendSuccess(res, result.items, 200, { nextCursor: result.nextCursor, hasMore: result.hasMore });
  } catch (err) { next(err); }
}
