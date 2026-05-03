import { Request, Response, NextFunction } from 'express';
import * as analyticsService from './analytics.service';
import { sendSuccess } from '../../utils/response';

export async function getDashboard(req: Request, res: Response, next: NextFunction) {
  try {
    sendSuccess(res, await analyticsService.getDashboardSummary());
  } catch (err) { next(err); }
}

export async function getMyStats(req: Request, res: Response, next: NextFunction) {
  try {
    sendSuccess(res, await analyticsService.getSalesOfficerStats(req.user!.id));
  } catch (err) { next(err); }
}

export async function getStockAlerts(req: Request, res: Response, next: NextFunction) {
  try {
    const threshold = req.query.threshold ? Number(req.query.threshold) : 10;
    sendSuccess(res, await analyticsService.getStockAlerts(threshold));
  } catch (err) { next(err); }
}
