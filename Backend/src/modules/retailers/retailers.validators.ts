import { z } from 'zod';

export const createRetailerSchema = z.object({
  name: z.string().min(1).max(255),
  phone: z.string().min(7).max(20),
  address: z.string().max(512).optional(),
  gstin: z.string().length(15).regex(/^[A-Z0-9]{15}$/, 'GSTIN must be 15 uppercase alphanumeric characters').optional(),
  creditLimit: z.number().min(0).default(0),
  isDirectSale: z.boolean().default(false),
  salesOfficerIds: z.array(z.string().uuid()).optional(),
});

export const updateRetailerSchema = createRetailerSchema.partial();

export const listRetailersQuerySchema = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  search: z.string().optional(),
  salesOfficerId: z.string().uuid().optional(),
});
