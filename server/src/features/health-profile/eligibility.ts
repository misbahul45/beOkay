import type { Prisma } from "../../generated/prisma/client.ts";
import { healthProfileRepository } from "./health-profile.repository.ts";
import type { DiabetesType, DiagnosisStatus } from "./health-profile.schema.ts";
import { determineJourney, type RiskStatement } from "../cohort/cohort.policy.ts";
import { emitDomainEvent } from "../../infrastructure/queue/events.ts";

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

export async function refreshEligibility(db: Prisma.TransactionClient, userId: string) {
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
  const decision = determineJourney({
    diagnosisStatus: health.diagnosisStatus as DiagnosisStatus,
    diabetesType: health.diabetesType as DiabetesType | null,
    riskStatement: health.riskStatement as RiskStatement | null,
    birthYear: profile?.birthYear ?? null,
  });
  if (decision.journey !== health.journey) {
    const setAt = new Date();
    await db.healthProfile.update({ where: { userId }, data: { journey: decision.journey, journeySource: "user_statement", journeySetAt: setAt } });
    await emitDomainEvent(db, { userId, type: "journey.changed", dedupeKey: `journey:${userId}:${setAt.toISOString()}:${decision.journey}`, payload: { from: health.journey, to: decision.journey, reason: decision.reason, policyVersion: decision.policyVersion }, source: "user_statement" });
  }
}
