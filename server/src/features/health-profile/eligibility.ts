import type { Prisma } from "../../generated/prisma/client.ts";
import { healthProfileRepository } from "./health-profile.repository.ts";
import type { DiabetesType, DiagnosisStatus } from "./health-profile.schema.ts";

export type EligibilityStatus = "eligible" | "needs_review" | "unknown";

export function computeEligibility(
  input: { diagnosisStatus: DiagnosisStatus; diabetesType: DiabetesType | null; birthYear: number | null },
  currentYear = new Date().getUTCFullYear(),
): EligibilityStatus {
  if (input.diagnosisStatus === "unknown" || input.diagnosisStatus === "undisclosed") return "unknown";
  const isAdult = input.birthYear !== null && currentYear - input.birthYear >= 18;
  if (input.diagnosisStatus === "diagnosed" && input.diabetesType === "type_2" && isAdult) return "eligible";
  return "needs_review";
}

export async function refreshEligibility(db: Pick<Prisma.TransactionClient, "healthProfile" | "userProfile">, userId: string) {
  const [health, profile] = await Promise.all([
    healthProfileRepository.find(userId, db),
    db.userProfile.findUnique({ where: { userId }, select: { birthYear: true } }),
  ]);
  if (!health) return;
  const eligibilityStatus = computeEligibility({
    diagnosisStatus: health.diagnosisStatus as DiagnosisStatus,
    diabetesType: health.diabetesType as DiabetesType | null,
    birthYear: profile?.birthYear ?? null,
  });
  if (eligibilityStatus !== health.eligibilityStatus) await healthProfileRepository.setEligibility(db, userId, eligibilityStatus);
}
