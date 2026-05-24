import { z } from 'zod';

export const recordPaymentSchema = z.object({
  orderId: z.string().uuid().optional(),
  retailerId: z.string().uuid(),
  companyId: z.string().uuid().optional(),
  amount: z.number().positive(),
  paymentDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Must be YYYY-MM-DD'),
  method: z.enum(['cash', 'upi', 'bank_transfer', 'cheque', 'other']),
  referenceNo: z.string().max(128).optional(),
  idempotencyKey: z.string().max(128).optional(),
  notes: z.string().max(512).optional(),
});

export const listPaymentsQuerySchema = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  orderId: z.string().uuid().optional(),
  retailerId: z.string().uuid().optional(),
  search: z.string().max(128).optional(),
});
