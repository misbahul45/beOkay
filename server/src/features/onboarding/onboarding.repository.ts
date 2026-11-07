import type { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";

type Db = Pick<Prisma.TransactionClient, "onboardingProgress" | "userProfile" | "healthProfile" | "userSettings" | "users" | "consentRecord">;

export type ProgressRow = { introSeenAt: Date | null; completedAt: Date | null; version: number };

const select = { introSeenAt: true, completedAt: true, version: true } as const;

export const onboardingRepository = {
  findProgress(userId: string, db: Db = prisma): Promise<ProgressRow | null> {
    return db.onboardingProgress.findUnique({ where: { userId }, select });
  },
  ensureProgress(db: Db, userId: string): Promise<ProgressRow> {
    return db.onboardingProgress.upsert({ where: { userId }, create: { userId }, update: {}, select });
  },
  async lockProgress(db: Pick<Prisma.TransactionClient, "$queryRaw">, userId: string) {
    await db.$queryRaw`SELECT 1 FROM onboarding_progress WHERE user_id = ${userId}::uuid FOR UPDATE`;
  },
  async markIntroSeen(db: Db, userId: string): Promise<ProgressRow> {
    return db.onboardingProgress.update({
      where: { userId },
      data: { introSeenAt: new Date(), version: { increment: 1 } },
      select,
    });
  },
  async markCompleted(db: Db, userId: string): Promise<ProgressRow> {
    return db.onboardingProgress.update({
      where: { userId },
      data: { completedAt: new Date(), version: { increment: 1 } },
      select,
    });
  },
  async sectionPresence(userId: string, db: Db = prisma) {
    const [user, profile, health, settings] = await Promise.all([
      db.users.findUnique({ where: { id: userId }, select: { emailVerified: true } }),
      db.userProfile.findUnique({ where: { userId }, select: { id: true } }),
      db.healthProfile.findUnique({ where: { userId }, select: { id: true } }),
      db.userSettings.findUnique({ where: { userId }, select: { userId: true } }),
    ]);
    return {
      emailVerified: user?.emailVerified ?? false,
      personalProfile: profile !== null,
      healthProfile: health !== null,
      preferences: settings !== null,
    };
  },
};
