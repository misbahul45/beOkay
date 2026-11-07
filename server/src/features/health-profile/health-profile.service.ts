import { prisma } from "../../infrastructure/database/prisma.ts";
import { conflict, unprocessable } from "../../shared/errors/app-error.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { consentService } from "../consent/consent.service.ts";
import { computeEligibility } from "./eligibility.ts";
import { healthProfileRepository, type HealthProfileRow } from "./health-profile.repository.ts";
import type {
  DiabetesType,
  DiagnosisStatus,
  PatchHealthProfileInput,
  PutHealthProfileInput,
  TreatmentContext,
} from "./health-profile.schema.ts";

type Candidate = {
  diagnosisStatus: DiagnosisStatus;
  diabetesType: DiabetesType | null;
  diagnosedYear: number | null;
  treatmentContext: TreatmentContext[];
};

export type HealthProfileView = {
  exists: boolean;
  diagnosisStatus: DiagnosisStatus | null;
  diabetesType: DiabetesType | null;
  diagnosedYear: number | null;
  treatmentContext: TreatmentContext[];
  provenance: { source: "user_reported"; clinicallyVerified: false };
  eligibilityStatus: string;
  createdAt: string | null;
  updatedAt: string | null;
};

const HEALTH_PURPOSE = "health_data_processing" as const;

function toView(row: HealthProfileRow | null): HealthProfileView {
  return {
    exists: row !== null,
    diagnosisStatus: (row?.diagnosisStatus as DiagnosisStatus | undefined) ?? null,
    diabetesType: (row?.diabetesType as DiabetesType | null | undefined) ?? null,
    diagnosedYear: row?.diagnosedYear ?? null,
    treatmentContext: (row?.treatmentContext ?? []) as TreatmentContext[],
    provenance: { source: "user_reported", clinicallyVerified: false },
    eligibilityStatus: row?.eligibilityStatus ?? "unknown",
    createdAt: row?.createdAt.toISOString() ?? null,
    updatedAt: row?.updatedAt.toISOString() ?? null,
  };
}

function validate(candidate: Candidate, birthYear: number | null) {
  if (candidate.diagnosisStatus !== "diagnosed" && (candidate.diabetesType !== null || candidate.diagnosedYear !== null)) {
    throw unprocessable("DETAILS_REQUIRE_DIAGNOSIS", "Tipe dan tahun diagnosis hanya diisi bila status diagnosis adalah terdiagnosis.");
  }
  if (candidate.diagnosedYear !== null && birthYear !== null && candidate.diagnosedYear < birthYear) {
    throw unprocessable("DIAGNOSIS_BEFORE_BIRTH", "Tahun diagnosis tidak boleh sebelum tahun lahir.");
  }
}

async function persist(userId: string, candidate: Candidate, changedFields: string[]) {
  return prisma.$transaction(async (tx) => {
    const profile = await tx.userProfile.findUnique({ where: { userId }, select: { birthYear: true } });
    const birthYear = profile?.birthYear ?? null;
    validate(candidate, birthYear);
    const row = await healthProfileRepository.upsert(tx, userId, {
      ...candidate,
      eligibilityStatus: computeEligibility({ ...candidate, birthYear }),
    });
    await recordAudit(tx, { userId, eventType: "health_profile_updated", metadata: { fields: changedFields } });
    return row;
  });
}

export const healthProfileService = {
  async get(userId: string): Promise<HealthProfileView> {
    await consentService.requireConsent(userId, HEALTH_PURPOSE);
    return toView(await healthProfileRepository.find(userId));
  },

  async put(userId: string, input: PutHealthProfileInput): Promise<HealthProfileView> {
    await consentService.requireConsent(userId, HEALTH_PURPOSE);
    const candidate: Candidate = {
      diagnosisStatus: input.diagnosisStatus,
      diabetesType: input.diabetesType ?? null,
      diagnosedYear: input.diagnosedYear ?? null,
      treatmentContext: input.treatmentContext ?? [],
    };
    return toView(await persist(userId, candidate, ["diagnosisStatus", "diabetesType", "diagnosedYear", "treatmentContext"]));
  },

  async patch(userId: string, input: PatchHealthProfileInput): Promise<HealthProfileView> {
    await consentService.requireConsent(userId, HEALTH_PURPOSE);
    const existing = await healthProfileRepository.find(userId);
    if (!existing) throw conflict("HEALTH_PROFILE_NOT_CREATED", "Profil kesehatan belum dibuat. Gunakan PUT untuk membuatnya.");
    const diagnosisStatus = input.diagnosisStatus ?? (existing.diagnosisStatus as DiagnosisStatus);
    const leavesDiagnosed = diagnosisStatus !== "diagnosed";
    if (leavesDiagnosed && (input.diabetesType != null || input.diagnosedYear != null)) {
      throw unprocessable("DETAILS_REQUIRE_DIAGNOSIS", "Tipe dan tahun diagnosis hanya diisi bila status diagnosis adalah terdiagnosis.");
    }
    const candidate: Candidate = {
      diagnosisStatus,
      diabetesType: leavesDiagnosed ? null : input.diabetesType !== undefined ? input.diabetesType : (existing.diabetesType as DiabetesType | null),
      diagnosedYear: leavesDiagnosed ? null : input.diagnosedYear !== undefined ? input.diagnosedYear : existing.diagnosedYear,
      treatmentContext: input.treatmentContext ?? (existing.treatmentContext as TreatmentContext[]),
    };
    const changed = (Object.keys(input) as (keyof PatchHealthProfileInput)[]).filter((key) => input[key] !== undefined);
    return toView(await persist(userId, candidate, changed));
  },
};
