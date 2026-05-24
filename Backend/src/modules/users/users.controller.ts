import { Request, Response, NextFunction } from 'express';
import * as usersService from './users.service';
import { sendSuccess } from '../../utils/response';

export async function listUsers(req: Request, res: Response, next: NextFunction) {
  try {
    const { cursor, limit, search } = req.query as any;
    const result = await usersService.listUsers({ cursor, limit: Number(limit) || 20, search });
    sendSuccess(res, result.items, 200, {
      nextCursor: result.nextCursor,
      hasMore: result.hasMore,
    });
  } catch (err) {
    next(err);
  }
}

export async function getUser(req: Request, res: Response, next: NextFunction) {
  try {
    const user = await usersService.getUserById(req.params.id);
    sendSuccess(res, user);
  } catch (err) {
    next(err);
  }
}

export async function assignRole(req: Request, res: Response, next: NextFunction) {
  try {
    await usersService.assignRole({
      userId: req.body.userId,
      roleId: req.body.roleId,
      actorId: req.user!.id,
    });
    sendSuccess(res, { message: 'Role assigned' });
  } catch (err) {
    next(err);
  }
}

export async function deactivateUser(req: Request, res: Response, next: NextFunction) {
  try {
    await usersService.deactivateUser(req.params.id, req.user!.id);
    sendSuccess(res, { message: 'User deactivated' });
  } catch (err) {
    next(err);
  }
}

export async function listRoles(req: Request, res: Response, next: NextFunction) {
  try {
    sendSuccess(res, await usersService.listRoles());
  } catch (err) { next(err); }
}

export async function listPermissions(req: Request, res: Response, next: NextFunction) {
  try {
    sendSuccess(res, await usersService.listPermissions());
  } catch (err) { next(err); }
}

export async function createRole(req: Request, res: Response, next: NextFunction) {
  try {
    const role = await usersService.createRole({ ...req.body, actorId: req.user!.id });
    sendSuccess(res, role, 201);
  } catch (err) { next(err); }
}

export async function updateRolePermissions(req: Request, res: Response, next: NextFunction) {
  try {
    const role = await usersService.updateRolePermissions(
      req.params.roleId,
      req.body.permissionIds,
      req.user!.id
    );
    sendSuccess(res, role);
  } catch (err) { next(err); }
}

export async function deleteRole(req: Request, res: Response, next: NextFunction) {
  try {
    await usersService.deleteRole(req.params.roleId, req.user!.id);
    sendSuccess(res, { message: 'Role deleted' });
  } catch (err) { next(err); }
}

export async function getActivityLog(req: Request, res: Response, next: NextFunction) {
  try {
    const { cursor, limit, search } = req.query as any;
    const result = await usersService.listActivityLog({
      cursor,
      limit: Number(limit) || 30,
      search,
    });
    sendSuccess(res, result.items, 200, {
      nextCursor: result.nextCursor,
      hasMore: result.hasMore,
    });
  } catch (err) { next(err); }
}
