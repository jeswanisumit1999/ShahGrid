import { z } from 'zod';

export const createVisitSchema = z.object({
  retailerId: z.string().uuid(),
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  notes: z.string().max(512).optional(),
});

export const listVisitsQuerySchema = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  retailerId: z.string().uuid().optional(),
  userId: z.string().uuid().optional(),
});
