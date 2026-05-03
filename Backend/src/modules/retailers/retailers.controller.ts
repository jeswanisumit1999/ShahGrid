import { Request, Response, NextFunction } from 'express';
import * as retailersService from './retailers.service';
import { sendSuccess } from '../../utils/response';
import { prisma } from '../../lib/prisma';

export async function listRetailers(req: Request, res: Response, next: NextFunction) {
  try {
    const { cursor, limit, search, salesOfficerId } = req.query as any;
    const canViewAll =
      req.user!.permissions.includes('retailers.manage') ||
      (await prisma.appSetting.findUnique({ where: { key: 'sales_officer_view_all_retailers' } }))
        ?.value === 'true';

    const result = await retailersService.listRetailers({
      cursor,
      limit: Number(limit) || 20,
      search,
      salesOfficerId,
      viewAll: !!canViewAll,
      requestingUserId: req.user!.id,
    });

    sendSuccess(res, result.items, 200, {
      nextCursor: result.nextCursor,
      hasMore: result.hasMore,
    });
  } catch (err) {
    next(err);
  }
}

export async function getRetailer(req: Request, res: Response, next: NextFunction) {
  try {
    const retailer = await retailersService.getRetailerById(req.params.id);
    sendSuccess(res, retailer);
  } catch (err) {
    next(err);
  }
}

export async function createRetailer(req: Request, res: Response, next: NextFunction) {
  try {
    const retailer = await retailersService.createRetailer(req.body, req.user!.id);
    sendSuccess(res, retailer, 201);
  } catch (err) {
    next(err);
  }
}

export async function updateRetailer(req: Request, res: Response, next: NextFunction) {
  try {
    const retailer = await retailersService.updateRetailer(req.params.id, req.body, req.user!.id);
    sendSuccess(res, retailer);
  } catch (err) {
    next(err);
  }
}
