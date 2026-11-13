export const COHORT_POLICY_VERSION = "cohort-policy-v1";

export const JOURNEYS = ["PREVENTION", "T2DM_SUPPORT", "WELLNESS", "UNDETERMINED"] as const;
export type Journey = (typeof JOURNEYS)[number];

export const RISK_STATEMENTS = ["prediabetes_told", "at_risk_told", "none", "undisclosed"] as const;
export type RiskStatement = (typeof RISK_STATEMENTS)[number];

export type JourneyReason =
  | "T2DM_DIAGNOSIS_REPORTED"
  | "CLINICIAN_RISK_STATEMENT_REPORTED"
  | "NO_DIAGNOSIS_REPORTED"
  | "DIAGNOSIS_NOT_DISCLOSED"
  | "OTHER_DIABETES_TYPE"
  | "AGE_UNKNOWN"
  | "UNDER_18"
  | "NO_HEALTH_PROFILE";

export type JourneyInput = {
  diagnosisStatus: "diagnosed" | "not_diagnosed" | "unknown" | "undisclosed";
  diabetesType: "type_2" | "type_1" | "other" | "unknown" | null;
  riskStatement: RiskStatement | null;
  birthYear: number | null;
};

export type JourneyDecision = { journey: Journey; reason: JourneyReason; policyVersion: string };

export function determineJourney(input: JourneyInput, currentYear = new Date().getUTCFullYear()): JourneyDecision {
  const decide = (journey: Journey, reason: JourneyReason): JourneyDecision => ({ journey, reason, policyVersion: COHORT_POLICY_VERSION });
  if (input.birthYear === null) return decide("UNDETERMINED", "AGE_UNKNOWN");
  if (currentYear - input.birthYear < 18) return decide("UNDETERMINED", "UNDER_18");
  if (input.diagnosisStatus === "diagnosed") {
    return input.diabetesType === "type_2" ? decide("T2DM_SUPPORT", "T2DM_DIAGNOSIS_REPORTED") : decide("UNDETERMINED", "OTHER_DIABETES_TYPE");
  }
  if (input.riskStatement === "prediabetes_told" || input.riskStatement === "at_risk_told") return decide("PREVENTION", "CLINICIAN_RISK_STATEMENT_REPORTED");
  return decide("WELLNESS", input.diagnosisStatus === "not_diagnosed" ? "NO_DIAGNOSIS_REPORTED" : "DIAGNOSIS_NOT_DISCLOSED");
}

export type JourneyCapabilities = {
  coaching: boolean;
  assistant: boolean;
  community: boolean;
  glucoseFeaturesVisible: boolean;
  medicationFeaturesVisible: boolean;
  screeningReminder: boolean;
};

export const JOURNEY_CAPABILITIES: Record<Journey, JourneyCapabilities> = {
  T2DM_SUPPORT: { coaching: true, assistant: true, community: true, glucoseFeaturesVisible: true, medicationFeaturesVisible: true, screeningReminder: false },
  PREVENTION: { coaching: true, assistant: true, community: true, glucoseFeaturesVisible: false, medicationFeaturesVisible: false, screeningReminder: true },
  WELLNESS: { coaching: true, assistant: true, community: true, glucoseFeaturesVisible: false, medicationFeaturesVisible: false, screeningReminder: false },
  UNDETERMINED: { coaching: false, assistant: false, community: false, glucoseFeaturesVisible: true, medicationFeaturesVisible: true, screeningReminder: false },
};

export const ALL_JOURNEYS: readonly Journey[] = JOURNEYS;
export const ACTIVE_JOURNEYS: readonly Journey[] = ["PREVENTION", "T2DM_SUPPORT", "WELLNESS"];

export function allowedFor(journey: Journey, allowed: readonly Journey[]): boolean {
  return allowed.includes(journey);
}

export function filterByJourney<T extends { allowedJourneys: readonly Journey[] }>(items: readonly T[], journey: Journey): T[] {
  return items.filter((i) => allowedFor(journey, i.allowedJourneys));
}

export const JOURNEY_LABELS: Record<Journey, string> = {
  PREVENTION: "Pencegahan",
  T2DM_SUPPORT: "Dukungan diabetes tipe 2",
  WELLNESS: "Gaya hidup sehat",
  UNDETERMINED: "Pencatatan saja",
};

export const JOURNEY_DESCRIPTIONS: Record<Journey, string> = {
  PREVENTION: "Kamu pernah diberi tahu tenaga kesehatan bahwa kamu berisiko atau prediabetes. beOkay membantu kebiasaan harian dan mengingatkan pemeriksaan rutin. Bukan diagnosis.",
  T2DM_SUPPORT: "Kamu melaporkan diagnosis diabetes tipe 2. beOkay membantu mencatat dan menjaga kebiasaan harian; pengobatan tetap bersama tim kesehatanmu.",
  WELLNESS: "Kamu ingin menjaga kebiasaan sehat. beOkay membantu aktivitas, makan, dan tidur sehari-hari.",
  UNDETERMINED: "beOkay belum dapat memberi saran untuk keadaanmu. Kamu tetap bisa mencatat dan melihat catatanmu.",
};
