import { prisma } from "../../infrastructure/database/prisma.ts";
import { conflict } from "../../shared/errors/app-error.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { consentService } from "../consent/consent.service.ts";
import { onboardingRepository, type ProgressRow } from "./onboarding.repository.ts";
import { deriveState, missingSteps, ONBOARDING_STEPS, type OnboardingSnapshot } from "./onboarding.state.ts";
import type { PatchOnboardingInput } from "./onboarding.schema.ts";

type Db = Parameters<typeof onboardingRepository.sectionPresence>[1];

async function buildSnapshot(userId: string, progress: ProgressRow | null, db: Db): Promise<OnboardingSnapshot> {
  const [presence, consentsOk] = await Promise.all([
    onboardingRepository.sectionPresence(userId, db),
    consentService.hasRequiredConsents(userId, db),
  ]);
  return {
    emailVerified: presence.emailVerified,
    introSeen: progress?.introSeenAt != null,
    completed: progress?.completedAt != null,
    steps: {
      consent: consentsOk,
      personal_profile: presence.personalProfile,
      health_profile: presence.healthProfile,
      preferences: presence.preferences,
    },
  };
}

function toView(snapshot: OnboardingSnapshot, progress: ProgressRow | null) {
  return {
    state: deriveState(snapshot),
    emailVerified: snapshot.emailVerified,
    steps: ONBOARDING_STEPS.map((key) => ({ key, done: snapshot.steps[key] })),
    introSeenAt: progress?.introSeenAt?.toISOString() ?? null,
    completedAt: progress?.completedAt?.toISOString() ?? null,
    version: progress?.version ?? 0,
    requiresConsentReview: snapshot.completed && !snapshot.steps.consent,
  };
}

export const onboardingService = {
  async get(userId: string) {
    const progress = await onboardingRepository.findProgress(userId);
    return toView(await buildSnapshot(userId, progress, prisma), progress);
  },

  async patch(userId: string, input: PatchOnboardingInput) {
    await prisma.$transaction(async (tx) => {
      await onboardingRepository.ensureProgress(tx, userId);
      await onboardingRepository.lockProgress(tx, userId);
      const current = await onboardingRepository.findProgress(userId, tx);
      if (input.expectedVersion !== undefined && current && input.expectedVersion !== current.version) {
        throw conflict("VERSION_CONFLICT", "Progres onboarding sudah berubah di tempat lain. Muat ulang lalu coba lagi.", {
          currentVersion: current.version,
        });
      }
      if (input.introSeen && current?.introSeenAt == null) await onboardingRepository.markIntroSeen(tx, userId);
    });
    return this.get(userId);
  },

  async complete(userId: string) {
    await prisma.$transaction(async (tx) => {
      await onboardingRepository.ensureProgress(tx, userId);
      await onboardingRepository.lockProgress(tx, userId);
      const progress = await onboardingRepository.findProgress(userId, tx);
      if (progress?.completedAt) return;
      const snapshot = await buildSnapshot(userId, progress, tx);
      if (!snapshot.emailVerified) throw conflict("EMAIL_NOT_VERIFIED", "Verifikasi email dulu sebelum menyelesaikan onboarding.");
      const missing = missingSteps(snapshot);
      if (missing.length > 0) throw conflict("ONBOARDING_INCOMPLETE", "Masih ada langkah yang belum selesai.", { missingSteps: missing });
      await onboardingRepository.markCompleted(tx, userId);
      await recordAudit(tx, { userId, eventType: "onboarding_completed" });
    });
    return this.get(userId);
  },
};
