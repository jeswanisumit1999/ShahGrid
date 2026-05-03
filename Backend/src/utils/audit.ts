import { PrismaClient } from '@prisma/client';

interface AuditParams {
  actorId: string;
  action: string;
  entityType: string;
  entityId: string;
  diff?: Record<string, unknown>;
}

/**
 * Writes an append-only audit record. Always call inside an existing transaction
 * so the audit entry is atomically tied to the business operation.
 */
export async function writeAuditLog(
  tx: Omit<PrismaClient, '$connect' | '$disconnect' | '$on' | '$transaction' | '$use' | '$extends'>,
  params: AuditParams
) {
  await tx.auditLog.create({
    data: {
      actorId: params.actorId,
      action: params.action,
      entityType: params.entityType,
      entityId: params.entityId,
      diff: params.diff ? JSON.parse(JSON.stringify(params.diff)) : undefined,
    },
  });
}
