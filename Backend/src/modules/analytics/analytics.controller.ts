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
    sendSuccess(res, await analyticsService.getStockAlerts());
  } catch (err) { next(err); }
}

export async function getGodownStats(req: Request, res: Response, next: NextFunction) {
  try {
    sendSuccess(res, await analyticsService.getGodownStats());
  } catch (err) { next(err); }
}
