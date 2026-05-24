export type ErrorCode =
  | 'VALIDATION_ERROR'
  | 'UNAUTHORIZED'
  | 'FORBIDDEN'
  | 'NOT_FOUND'
  | 'CONFLICT'
  | 'CREDIT_LIMIT_EXCEEDED'
  | 'INSUFFICIENT_STOCK'
  | 'PAID_AMOUNT_EXCEEDS_TOTAL'
  | 'INVALID_STATUS_TRANSITION'
  | 'INVALID_QUANTITY'
  | 'INVALID_SPLIT_STATUS'
  | 'INVALID_ITEMS'
  | 'SPLIT_TOO_MANY'
  | 'SYSTEM_ROLE'
  | 'ROLE_IN_USE'
  | 'DUPLICATE_PAYMENT'
  | 'IDEMPOTENCY_CONFLICT'
  | 'INTERNAL_ERROR';

export class AppError extends Error {
  public readonly statusCode: number;
  public readonly errorCode: ErrorCode;
  public readonly isOperational: boolean;

  constructor(message: string, statusCode: number, errorCode: ErrorCode) {
    super(message);
    this.statusCode = statusCode;
    this.errorCode = errorCode;
    this.isOperational = true;
    Error.captureStackTrace(this, this.constructor);
  }

  static badRequest(message: string, errorCode: ErrorCode = 'VALIDATION_ERROR') {
    return new AppError(message, 400, errorCode);
  }

  static unauthorized(message = 'Authentication required') {
    return new AppError(message, 401, 'UNAUTHORIZED');
  }

  static forbidden(message = 'Insufficient permissions') {
    return new AppError(message, 403, 'FORBIDDEN');
  }

  static notFound(resource: string) {
    return new AppError(`${resource} not found`, 404, 'NOT_FOUND');
  }

  static conflict(message: string, errorCode: ErrorCode = 'CONFLICT') {
    return new AppError(message, 409, errorCode);
  }

  static internal(message = 'Internal server error') {
    return new AppError(message, 500, 'INTERNAL_ERROR');
  }
}
