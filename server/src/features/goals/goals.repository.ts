import type { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
export const goalsRepository = {
  find(userId: string, id: string, db: Prisma.TransactionClient = prisma) { return db.behaviorGoal.findFirst({ where: { userId, id } }); },
  checkin(userId: string, goalId: string, id: string, db: Prisma.TransactionClient = prisma) { return db.goalCheckin.findFirst({ where: { userId, goalId, id } }); },
};
