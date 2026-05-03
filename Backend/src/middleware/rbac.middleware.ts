import { Request, Response, NextFunction } from 'express';
import { AppError } from '../errors/AppError';

/**
 * Factory that returns a middleware enforcing a single permission.
 * Usage: router.post('/', authenticate, requirePermission('orders', 'create'), controller)
 */
export function requirePermission(resource: string, action: string) {
  const required = `${resource}.${action}`;
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!req.user) {
      return next(AppError.unauthorized());
    }
    if (!req.user.permissions.includes(required)) {
      return next(AppError.forbidden(`Missing permission: ${required}`));
    }
    next();
  };
}

/** Convenience: require any one of the given roles. */
export function requireRole(...roles: string[]) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!req.user) {
      return next(AppError.unauthorized());
    }
    const hasRole = roles.some((r) => req.user!.roles.includes(r));
    if (!hasRole) {
      return next(AppError.forbidden(`Required role: ${roles.join(' or ')}`));
    }
    next();
  };
}
