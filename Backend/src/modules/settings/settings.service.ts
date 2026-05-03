import { prisma } from '../../lib/prisma';
import { AppError } from '../../errors/AppError';
import { writeAuditLog } from '../../utils/audit';

export async function listSettings() {
  return prisma.appSetting.findMany({ orderBy: { key: 'asc' } });
}

export async function updateSetting(key: string, value: string, actorId: string) {
  const setting = await prisma.appSetting.findUnique({ where: { key } });
  if (!setting) throw AppError.notFound(`Setting "${key}"`);

  return prisma.$transaction(async (tx) => {
    const updated = await tx.appSetting.update({
      where: { key },
      data: { value, updatedBy: actorId },
    });

    await writeAuditLog(tx, {
      actorId,
      action: 'update_setting',
      entityType: 'AppSetting',
      entityId: key,
      diff: { from: setting.value, to: value },
    });

    return updated;
  });
}
