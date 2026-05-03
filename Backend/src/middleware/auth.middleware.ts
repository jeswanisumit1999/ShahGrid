import { Request, Response, NextFunction } from 'express';
import { verifyAccessToken } from '../utils/jwt';
import { AppError } from '../errors/AppError';

export function authenticate(req: Request, _res: Response, next: NextFunction) {
  try {
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      throw AppError.unauthorized();
    }

    const token = header.slice(7);
    const payload = verifyAccessToken(token);

    req.user = {
      id: payload.sub,
      email: payload.email,
      name: '', // name is not in the JWT payload — fetch from DB if needed
      roles: payload.roles,
      permissions: payload.permissions,
    };

    next();
  } catch (err) {
    next(AppError.unauthorized('Invalid or expired token'));
  }
}
