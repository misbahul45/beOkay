import type { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import type { EligibilityStatus } from "./eligibility.ts";

type Db = Pick<Prisma.TransactionClient, "healthProfile">;

const select = {
  diagnosisStatus: true,
  diabetesType: true,
  diagnosedYear: true,
  treatmentContext: true,
  dataSource: true,
  eligibilityStatus: true,
  riskStatement: true,
  journey: true,
  journeySource: true,
  journeySetAt: true,
  createdAt: true,
  updatedAt: true,
} as const;

export type HealthProfileRow = {
  diagnosisStatus: string;
  diabetesType: string | null;
  diagnosedYear: number | null;
  treatmentContext: string[];
  dataSource: string;
  eligibilityStatus: string;
  riskStatement: string | null;
  journey: string;
  journeySource: string | null;
  journeySetAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
};

export type HealthProfileData = {
  diagnosisStatus: string;
  diabetesType: string | null;
  diagnosedYear: number | null;
  treatmentContext: string[];
  eligibilityStatus: EligibilityStatus;
  riskStatement: string | null;
  journey: string;
  journeySource: string;
  journeySetAt: Date;
};

export const healthProfileRepository = {
  find(userId: string, db: Db = prisma): Promise<HealthProfileRow | null> {
    return db.healthProfile.findUnique({ where: { userId }, select });
  },
  upsert(db: Db, userId: string, data: HealthProfileData): Promise<HealthProfileRow> {
    return db.healthProfile.upsert({
      where: { userId },
      create: { userId, ...data, dataSource: "user_reported" },
      update: { ...data, dataSource: "user_reported" },
      select,
    });
  },
  async setEligibility(db: Db, userId: string, eligibilityStatus: EligibilityStatus) {
    await db.healthProfile.update({ where: { userId }, data: { eligibilityStatus } });
  },
};
