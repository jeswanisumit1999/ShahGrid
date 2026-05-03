import { z } from 'zod';

export const createReturnSchema = z.object({
  orderId: z.string().uuid(),
  retailerId: z.string().uuid(),
  reason: z.string().max(512).optional(),
  items: z
    .array(
      z.object({
        orderItemId: z.string().uuid(),
        quantity: z.number().int().positive(),
      })
    )
    .min(1, 'Return must have at least one item'),
});

export const listReturnsQuerySchema = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  orderId: z.string().uuid().optional(),
  retailerId: z.string().uuid().optional(),
});
