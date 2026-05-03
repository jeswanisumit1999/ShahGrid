import { z } from 'zod';

export const createOrderSchema = z.object({
  retailerId: z.string().uuid(),
  salesOfficerId: z.string().uuid(),
  isDirectSale: z.boolean().default(false),
  overrideCompanyId: z.string().uuid().optional(),
  notes: z.string().max(1024).optional(),
  items: z
    .array(
      z.object({
        productId: z.string().uuid(),
        quantity: z.number().int().positive(),
        unitPrice: z.number().positive(),
      })
    )
    .min(1, 'Order must have at least one item'),
});

export const listOrdersQuerySchema = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  retailerId: z.string().uuid().optional(),
  salesOfficerId: z.string().uuid().optional(),
});
