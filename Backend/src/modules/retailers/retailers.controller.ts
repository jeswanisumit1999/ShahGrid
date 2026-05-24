import { Request, Response, NextFunction } from 'express';
import * as retailersService from './retailers.service';
import { sendSuccess } from '../../utils/response';
import { prisma } from '../../lib/prisma';

export async function listRetailers(req: Request, res: Response, next: NextFunction) {
  try {
    const { cursor, limit, search, salesOfficerId } = req.query as any;
    const canViewAll =
      req.user!.permissions.includes('shipments.manage') ||
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
    const canSetCreditLimit = req.user!.permissions.includes('retailers.credit_limit');
    const body = canSetCreditLimit ? req.body : { ...req.body, creditLimit: 10000 };
    const retailer = await retailersService.createRetailer(body, req.user!.id);
    sendSuccess(res, retailer, 201);
  } catch (err) {
    next(err);
  }
}

export async function updateRetailer(req: Request, res: Response, next: NextFunction) {
  try {
    const canSetCreditLimit = req.user!.permissions.includes('retailers.credit_limit');
    const { creditLimit, ...rest } = req.body;
    const body = canSetCreditLimit ? req.body : rest;
    const retailer = await retailersService.updateRetailer(req.params.id, body, req.user!.id);
    sendSuccess(res, retailer);
  } catch (err) {
    next(err);
  }
}

export async function deleteRetailer(req: Request, res: Response, next: NextFunction) {
  try {
    await retailersService.deleteRetailer(req.params.id, req.user!.id);
    sendSuccess(res, null, 204);
  } catch (err) {
    next(err);
  }
}

export async function getRetailerLedger(req: Request, res: Response, next: NextFunction) {
  try {
    const { cursor, limit } = req.query as any;
    const result = await retailersService.getRetailerLedger(req.params.id, {
      cursor,
      limit: Number(limit) || 20,
    });
    sendSuccess(res, result.items, 200, {
      nextCursor: result.nextCursor,
      hasMore: result.hasMore,
      retailer: result.retailer,
    });
  } catch (err) { next(err); }
}
