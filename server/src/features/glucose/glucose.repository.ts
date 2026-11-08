import type { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
export const glucoseRepository = {
  find(userId: string, id: string, db: Prisma.TransactionClient = prisma) {
    return db.glucoseObservation.findFirst({ where: { userId, id } });
  },
  async dateIds(
    userId: string,
    date: string,
    timezone: string,
    db: Prisma.TransactionClient = prisma,
    archived = false,
  ) {
    const rows = await db.$queryRaw<
      { id: string }[]
    >`SELECT id FROM glucose_observations WHERE user_id=${userId}::uuid AND (archived_at IS NOT NULL)=${archived} AND measured_at>=(${date}::date::timestamp AT TIME ZONE ${timezone}) AND measured_at<((${date}::date+1)::timestamp AT TIME ZONE ${timezone})`;
    return rows.map((row) => row.id);
  },
};
