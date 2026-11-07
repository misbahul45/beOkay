export const ONBOARDING_STATES = [
  "EMAIL_VERIFICATION_PENDING",
  "NOT_STARTED",
  "CONSENT_PENDING",
  "PERSONAL_PROFILE_PENDING",
  "HEALTH_PROFILE_PENDING",
  "PREFERENCES_PENDING",
  "READY_TO_COMPLETE",
  "COMPLETED",
] as const;
export type OnboardingState = (typeof ONBOARDING_STATES)[number];

export const ONBOARDING_STEPS = ["consent", "personal_profile", "health_profile", "preferences"] as const;
export type OnboardingStep = (typeof ONBOARDING_STEPS)[number];

export type OnboardingSnapshot = {
  emailVerified: boolean;
  introSeen: boolean;
  completed: boolean;
  steps: Record<OnboardingStep, boolean>;
};

export function missingSteps(snapshot: OnboardingSnapshot): OnboardingStep[] {
  return ONBOARDING_STEPS.filter((step) => !snapshot.steps[step]);
}

export function deriveState(snapshot: OnboardingSnapshot): OnboardingState {
  if (snapshot.completed) return "COMPLETED";
  if (!snapshot.emailVerified) return "EMAIL_VERIFICATION_PENDING";
  const missing = missingSteps(snapshot);
  if (missing.length === ONBOARDING_STEPS.length && !snapshot.introSeen) return "NOT_STARTED";
  switch (missing[0]) {
    case "consent":
      return "CONSENT_PENDING";
    case "personal_profile":
      return "PERSONAL_PROFILE_PENDING";
    case "health_profile":
      return "HEALTH_PROFILE_PENDING";
    case "preferences":
      return "PREFERENCES_PENDING";
    default:
      return "READY_TO_COMPLETE";
  }
}
