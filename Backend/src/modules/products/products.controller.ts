import { Request, Response, NextFunction } from 'express';
import * as productsService from './products.service';
import { sendSuccess } from '../../utils/response';

export async function listProducts(req: Request, res: Response, next: NextFunction) {
  try {
    const { cursor, limit, search, companyId, categoryId } = req.query as any;
    const result = await productsService.listProducts({ cursor, limit: Number(limit) || 20, search, companyId, categoryId });
    sendSuccess(res, result.items, 200, { nextCursor: result.nextCursor, hasMore: result.hasMore });
  } catch (err) { next(err); }
}

export async function getProduct(req: Request, res: Response, next: NextFunction) {
  try {
    sendSuccess(res, await productsService.getProductById(req.params.id));
  } catch (err) { next(err); }
}

export async function createProduct(req: Request, res: Response, next: NextFunction) {
  try {
    sendSuccess(res, await productsService.createProduct(req.body), 201);
  } catch (err) { next(err); }
}

export async function updateProduct(req: Request, res: Response, next: NextFunction) {
  try {
    sendSuccess(res, await productsService.updateProduct(req.params.id, req.body));
  } catch (err) { next(err); }
}

export async function deleteProduct(req: Request, res: Response, next: NextFunction) {
  try {
    await productsService.deleteProduct(req.params.id);
    sendSuccess(res, null, 204);
  } catch (err) { next(err); }
}

export async function adjustStock(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await productsService.adjustStock(
      req.params.id,
      req.body.delta,
      req.body.reason,
      req.user!.id
    );
    sendSuccess(res, result);
  } catch (err) { next(err); }
}

export async function listCompanies(_req: Request, res: Response, next: NextFunction) {
  try {
    sendSuccess(res, await productsService.listCompanies());
  } catch (err) { next(err); }
}

export async function createCompany(req: Request, res: Response, next: NextFunction) {
  try {
    sendSuccess(res, await productsService.createCompany(req.body.name, req.body.gstin, req.body.phone, req.body.address), 201);
  } catch (err) { next(err); }
}

export async function listCategories(_req: Request, res: Response, next: NextFunction) {
  try {
    sendSuccess(res, await productsService.listCategories());
  } catch (err) { next(err); }
}

export async function createCategory(req: Request, res: Response, next: NextFunction) {
  try {
    sendSuccess(res, await productsService.createCategory(req.body.name), 201);
  } catch (err) { next(err); }
}

export async function listBrands(_req: Request, res: Response, next: NextFunction) {
  try {
    sendSuccess(res, await productsService.listBrands());
  } catch (err) { next(err); }
}

export async function getStockLedger(req: Request, res: Response, next: NextFunction) {
  try {
    const { cursor, limit, direction } = req.query as any;
    const result = await productsService.getStockLedger(req.params.id, {
      cursor,
      limit: Number(limit) || 20,
      direction,
    });
    sendSuccess(res, result.items, 200, {
      nextCursor: result.nextCursor,
      hasMore: result.hasMore,
      product: result.product,
    });
  } catch (err) { next(err); }
}
