import type { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import type { ConsentPurpose, ConsentSource } from "./consent.policy.ts";

type Db = Pick<Prisma.TransactionClient, "consentRecord">;

export type ConsentRow = {
  id: string;
  purpose: string;
  policyVersion: string;
  grantedAt: Date;
  withdrawnAt: Date | null;
  source: string;
};

const select = { id: true, purpose: true, policyVersion: true, grantedAt: true, withdrawnAt: true, source: true } as const;

export const consentRepository = {
  listAll(userId: string, db: Db = prisma): Promise<ConsentRow[]> {
    return db.consentRecord.findMany({ where: { userId }, orderBy: { grantedAt: "desc" }, select });
  },
  listActive(userId: string, db: Db = prisma): Promise<ConsentRow[]> {
    return db.consentRecord.findMany({ where: { userId, withdrawnAt: null }, select });
  },
  async hasActive(userId: string, purpose: ConsentPurpose, db: Db = prisma): Promise<boolean> {
    const found = await db.consentRecord.findFirst({ where: { userId, purpose, withdrawnAt: null }, select: { id: true } });
    return found !== null;
  },
  findActive(userId: string, purpose: ConsentPurpose, db: Db): Promise<ConsentRow | null> {
    return db.consentRecord.findFirst({ where: { userId, purpose, withdrawnAt: null }, select });
  },
  create(
    db: Db,
    data: { userId: string; purpose: ConsentPurpose; policyVersion: string; source: ConsentSource; grantedAt: Date },
  ) {
    return db.consentRecord.create({ data, select });
  },
  async withdraw(db: Db, id: string, at: Date) {
    await db.consentRecord.update({ where: { id }, data: { withdrawnAt: at } });
  },
};
