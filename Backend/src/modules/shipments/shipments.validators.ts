import { z } from 'zod';

export const SHIPMENT_STATUSES = [
  'Pending Stock Verification',
  'Pending Stock Availability',
  'Ready for Dispatch',
  'Delivered',
  'Cancelled',
  'Returned',
] as const;

export const updateShipmentStatusSchema = z.object({
  status: z.enum(SHIPMENT_STATUSES),
  notes: z.string().max(1024).optional(),
  // When true, allows stock to go negative on "Ready for Dispatch" (user-confirmed override)
  force: z.boolean().optional(),
  // Per-item quantity adjustments — only honoured when transitioning to Delivered
  adjustments: z
    .array(
      z.object({
        shipmentItemId: z.string().uuid(),
        actualQuantity: z.number().int().min(0),
      })
    )
    .optional(),
});

export const listShipmentsQuerySchema = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  orderId: z.string().uuid().optional(),
  status: z.enum(SHIPMENT_STATUSES).optional(),
  companyId: z.string().uuid().optional(),
});

export const splitShipmentSchema = z.object({
  // IDs of ShipmentItems to move into the new child shipment
  itemIds: z.array(z.string().uuid()).min(1),
});
