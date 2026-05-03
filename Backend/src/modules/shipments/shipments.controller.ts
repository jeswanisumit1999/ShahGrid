import { Request, Response, NextFunction } from 'express';
import * as shipmentsService from './shipments.service';
import { sendSuccess } from '../../utils/response';

export async function listShipments(req: Request, res: Response, next: NextFunction) {
  try {
    const { cursor, limit, orderId, status, companyId } = req.query as any;
    const result = await shipmentsService.listShipments({
      cursor, limit: Number(limit) || 20, orderId, status, companyId,
    });
    sendSuccess(res, result.items, 200, { nextCursor: result.nextCursor, hasMore: result.hasMore });
  } catch (err) { next(err); }
}

export async function getShipment(req: Request, res: Response, next: NextFunction) {
  try {
    sendSuccess(res, await shipmentsService.getShipmentById(req.params.id));
  } catch (err) { next(err); }
}

export async function updateStatus(req: Request, res: Response, next: NextFunction) {
  try {
    const updated = await shipmentsService.updateShipmentStatus(
      req.params.id,
      req.body.status,
      req.body.notes,
      req.user!.id,
      req.user!.roles,
      req.body.adjustments,
    );
    sendSuccess(res, updated);
  } catch (err) { next(err); }
}

export async function splitShipment(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await shipmentsService.splitShipment(
      req.params.id,
      req.body.itemIds,
      req.user!.id,
    );
    sendSuccess(res, result, 201);
  } catch (err) { next(err); }
}
