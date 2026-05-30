import { z } from 'zod';

export const createOrderSchema = z.object({
  retailerId: z.string().uuid(),
  salesOfficerId: z.string().uuid(),
  isDirectSale: z.boolean().default(false),
  paidAmount: z.number().min(0).optional(),
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

export const updateOrderItemSchema = z.object({
  quantity: z.number().int().min(1),
  unitPrice: z.number().positive().optional(),
});

export const addOrderItemSchema = z.object({
  productId: z.string().uuid(),
  quantity: z.number().int().positive(),
  unitPrice: z.number().positive(),
});

export const updateOrderSchema = z.object({
  notes: z.string().max(1024).optional().nullable(),
});

export const listOrdersQuerySchema = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  retailerId: z.string().uuid().optional(),
  salesOfficerId: z.string().uuid().optional(),
  search: z.string().max(100).optional(),
});
