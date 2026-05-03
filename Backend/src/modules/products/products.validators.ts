import { z } from 'zod';

export const createProductSchema = z.object({
  companyId: z.string().uuid(),
  categoryId: z.string().uuid().optional(),
  name: z.string().min(1).max(255),
  sku: z.string().min(1).max(64).optional(),
  brand: z.string().max(128).optional(),
  price: z.number().positive(),
  stockQuantity: z.number().int().min(0).default(0),
});

export const updateProductSchema = createProductSchema.partial().omit({ sku: true });

export const adjustStockSchema = z.object({
  delta: z.number().int().refine((v) => v !== 0, 'Delta must be non-zero'),
  reason: z.string().max(512).optional(),
});

export const listProductsQuerySchema = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  search: z.string().optional(),
  companyId: z.string().uuid().optional(),
  categoryId: z.string().uuid().optional(),
});
