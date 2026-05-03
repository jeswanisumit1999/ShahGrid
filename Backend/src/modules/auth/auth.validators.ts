import { z } from 'zod';

export const googleCallbackSchema = z.object({
  code: z.string().min(1),
});

export const refreshTokenSchema = z.object({
  refreshToken: z.string().min(1),
});
