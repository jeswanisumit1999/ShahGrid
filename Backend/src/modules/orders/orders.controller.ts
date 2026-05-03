import { Request, Response, NextFunction } from 'express';
import * as ordersService from './orders.service';
import { sendSuccess } from '../../utils/response';

export async function createOrder(req: Request, res: Response, next: NextFunction) {
  try {
    const order = await ordersService.createOrder(req.body, req.user!.id);
    sendSuccess(res, order, 201);
  } catch (err) { next(err); }
}

export async function listOrders(req: Request, res: Response, next: NextFunction) {
  try {
    const { cursor, limit, retailerId, salesOfficerId } = req.query as any;
    const result = await ordersService.listOrders({ cursor, limit: Number(limit) || 20, retailerId, salesOfficerId });
    sendSuccess(res, result.items, 200, { nextCursor: result.nextCursor, hasMore: result.hasMore });
  } catch (err) { next(err); }
}

export async function getOrder(req: Request, res: Response, next: NextFunction) {
  try {
    sendSuccess(res, await ordersService.getOrderById(req.params.id));
  } catch (err) { next(err); }
}
