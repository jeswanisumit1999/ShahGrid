-- Rename dispatched_at → ready_at (reflects "Ready for Dispatch" status)
ALTER TABLE "shipments" RENAME COLUMN "dispatched_at" TO "ready_at";

-- Add returned_at timestamp
ALTER TABLE "shipments" ADD COLUMN "returned_at" TIMESTAMPTZ;
