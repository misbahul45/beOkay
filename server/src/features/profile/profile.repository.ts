import type { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";

type Db = Pick<Prisma.TransactionClient, "userProfile" | "users">;

export const profileRepository = {
  find(userId: string, db: Db = prisma) {
    return db.userProfile.findUnique({ where: { userId }, select: { birthYear: true, createdAt: true, updatedAt: true } });
  },
  async findName(userId: string, db: Db = prisma): Promise<string | null> {
    const user = await db.users.findUnique({ where: { id: userId }, select: { name: true } });
    return user?.name ?? null;
  },
  upsert(db: Db, userId: string, birthYear: number | null | undefined) {
    return db.userProfile.upsert({
      where: { userId },
      create: { userId, birthYear: birthYear ?? null },
      update: birthYear === undefined ? {} : { birthYear },
      select: { birthYear: true, createdAt: true, updatedAt: true },
    });
  },
};
