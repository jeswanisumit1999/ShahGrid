import { z } from 'zod';

export const createDirectSaleSchema = z.object({
  customerName: z.string().min(1).max(255),
  salesOfficerId: z.string().uuid(),
  amountPaid: z.number().min(0).optional(),
  notes: z.string().max(1024).optional(),
  items: z
    .array(
      z.object({
        productId: z.string().uuid(),
        quantity: z.number().int().positive(),
        unitPrice: z.number().positive(),
      }),
    )
    .min(1, 'Direct sale must have at least one item'),
});

export const listDirectSalesQuerySchema = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  salesOfficerId: z.string().uuid().optional(),
  search: z.string().max(100).optional(),
});
