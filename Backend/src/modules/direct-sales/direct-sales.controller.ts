import { Request, Response, NextFunction } from 'express';
import * as service from './direct-sales.service';
import { sendSuccess } from '../../utils/response';

export async function createDirectSale(req: Request, res: Response, next: NextFunction) {
  try {
    const sale = await service.createDirectSale({ ...req.body, createdById: req.user!.id });
    sendSuccess(res, sale, 201);
  } catch (err) { next(err); }
}

export async function listDirectSales(req: Request, res: Response, next: NextFunction) {
  try {
    const { cursor, limit, salesOfficerId, search } = req.query as any;
    const result = await service.listDirectSales({ cursor, limit: Number(limit) || 20, salesOfficerId, search });
    sendSuccess(res, result.items, 200, { nextCursor: result.nextCursor, hasMore: result.hasMore });
  } catch (err) { next(err); }
}

export async function getDirectSale(req: Request, res: Response, next: NextFunction) {
  try {
    sendSuccess(res, await service.getDirectSaleById(req.params.id));
  } catch (err) { next(err); }
}

export async function getDirectSaleChallan(req: Request, res: Response, next: NextFunction) {
  try {
    const pdf = await service.generateDirectSaleChallanPdf(req.params.id);
    res.set({ 'Content-Type': 'application/pdf', 'Content-Length': pdf.length });
    res.send(pdf);
  } catch (err) { next(err); }
}
