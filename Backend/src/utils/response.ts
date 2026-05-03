import { Response } from 'express';

interface PaginationMeta {
  nextCursor: string | null;
  hasMore: boolean;
  total?: number;
}

export function sendSuccess<T>(
  res: Response,
  data: T,
  statusCode = 200,
  meta?: PaginationMeta
) {
  res.status(statusCode).json({
    success: true,
    data,
    ...(meta && { pagination: meta }),
  });
}

export function sendError(
  res: Response,
  message: string,
  statusCode: number,
  errorCode: string
) {
  res.status(statusCode).json({
    success: false,
    error: { code: errorCode, message },
  });
}
