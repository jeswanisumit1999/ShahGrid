import { Request, Response, NextFunction } from 'express';
import * as ordersService from './orders.service';
import { sendSuccess } from '../../utils/response';

export async function createOrder(req: Request, res: Response, next: NextFunction) {
  try {
    const canDirectSale = req.user!.permissions.includes('orders.direct_sale');
    const body = {
      ...req.body,
      isDirectSale: canDirectSale ? (req.body.isDirectSale ?? false) : false,
      paidAmount: canDirectSale ? req.body.paidAmount : undefined,
    };
    const order = await ordersService.createOrder(body, req.user!.id);
    sendSuccess(res, order, 201);
  } catch (err) { next(err); }
}

export async function listOrders(req: Request, res: Response, next: NextFunction) {
  try {
    const { cursor, limit, retailerId, salesOfficerId, search } = req.query as any;
    const isSalesOfficer = req.user!.roles.includes('Sales Officer');
    const result = await ordersService.listOrders({
      cursor,
      limit: Number(limit) || 20,
      retailerId,
      salesOfficerId: isSalesOfficer ? undefined : salesOfficerId,
      assignedSalesOfficerId: isSalesOfficer ? req.user!.id : undefined,
      search,
    });
    sendSuccess(res, result.items, 200, { nextCursor: result.nextCursor, hasMore: result.hasMore });
  } catch (err) { next(err); }
}

export async function getOrder(req: Request, res: Response, next: NextFunction) {
  try {
    sendSuccess(res, await ordersService.getOrderById(req.params.id));
  } catch (err) { next(err); }
}

export async function updateOrderItem(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await ordersService.updateOrderItemQuantity(
      req.params.id,
      req.params.itemId,
      req.body.quantity,
      req.user!.id,
      req.body.unitPrice
    );
    sendSuccess(res, result);
  } catch (err) { next(err); }
}

export async function updateOrder(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await ordersService.updateOrderNotes(req.params.id, req.body.notes);
    sendSuccess(res, result);
  } catch (err) { next(err); }
}

export async function addOrderItem(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await ordersService.addOrderItem(req.params.id, req.body, req.user!.id);
    sendSuccess(res, result, 201);
  } catch (err) { next(err); }
}
