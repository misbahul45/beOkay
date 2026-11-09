import type { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
export const medicationRepository = {
  regimen(userId: string, id: string, db: Prisma.TransactionClient = prisma) { return db.medicationRegimen.findFirst({ where: { userId, id } }); },
  schedule(userId: string, regimenId: string, id: string, db: Prisma.TransactionClient = prisma) { return db.medicationSchedule.findFirst({ where: { userId, regimenId, id } }); },
  intake(userId: string, regimenId: string, id: string, db: Prisma.TransactionClient = prisma) { return db.medicationIntake.findFirst({ where: { userId, regimenId, id } }); },
};
