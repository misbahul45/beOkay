import type { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";

type Db = Pick<Prisma.TransactionClient, "userSettings">;

const select = { locale: true, timezone: true, glucoseUnit: true, textSize: true, reduceMotion: true, updatedAt: true } as const;

export type SettingsRow = {
  locale: string;
  timezone: string;
  glucoseUnit: string;
  textSize: string;
  reduceMotion: boolean;
  updatedAt: Date;
};

export const preferencesRepository = {
  find(userId: string, db: Db = prisma): Promise<SettingsRow | null> {
    return db.userSettings.findUnique({ where: { userId }, select });
  },
  upsert(db: Db, userId: string, data: Partial<Omit<SettingsRow, "updatedAt">>): Promise<SettingsRow> {
    return db.userSettings.upsert({ where: { userId }, create: { userId, ...data }, update: data, select });
  },
};
