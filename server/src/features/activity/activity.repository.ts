import type { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
export const activityRepository = {
  find(userId: string, id: string, db: Prisma.TransactionClient = prisma) {
    return db.activitySession.findFirst({ where: { userId, id } });
  },
  async periodIds(
    userId: string,
    startDate: string,
    endDate: string,
    timezone: string,
    db: Prisma.TransactionClient = prisma,
    archived = false,
  ) {
    const rows = await db.$queryRaw<
      { id: string }[]
    >`SELECT id FROM activity_sessions WHERE user_id=${userId}::uuid AND (archived_at IS NOT NULL)=${archived} AND started_at>=(${startDate}::date::timestamp AT TIME ZONE ${timezone}) AND started_at<(${endDate}::date::timestamp AT TIME ZONE ${timezone})`;
    return rows.map((r) => r.id);
  },
};
