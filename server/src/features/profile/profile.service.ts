import { prisma } from "../../infrastructure/database/prisma.ts";
import { notFound } from "../../shared/errors/app-error.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { auth } from "../auth/auth.ts";
import { healthProfileRepository } from "../health-profile/health-profile.repository.ts";
import { refreshEligibility } from "../health-profile/eligibility.ts";
import { profileRepository } from "./profile.repository.ts";
import type { UpdateProfileInput } from "./profile.schema.ts";

export type ProfileView = {
  exists: boolean;
  displayName: string;
  birthYear: number | null;
  completeness: { complete: boolean; missing: string[] };
  createdAt: string | null;
  updatedAt: string | null;
};

function completeness(birthYear: number | null) {
  const missing = birthYear === null ? ["birthYear"] : [];
  return { complete: missing.length === 0, missing };
}

export const profileService = {
  async get(userId: string): Promise<ProfileView> {
    const [name, profile] = await Promise.all([profileRepository.findName(userId), profileRepository.find(userId)]);
    if (name === null) throw notFound("USER_NOT_FOUND", "Akun tidak ditemukan.");
    const birthYear = profile?.birthYear ?? null;
    return {
      exists: profile !== null,
      displayName: name,
      birthYear,
      completeness: completeness(birthYear),
      createdAt: profile?.createdAt.toISOString() ?? null,
      updatedAt: profile?.updatedAt.toISOString() ?? null,
    };
  },

  async update(userId: string, headers: Headers, input: UpdateProfileInput): Promise<ProfileView> {
    if (input.displayName !== undefined) {
      await auth.api.updateUser({ headers, body: { name: input.displayName } });
    }
    await prisma.$transaction(async (tx) => {
      await profileRepository.upsert(tx, userId, input.birthYear);
      if (input.birthYear !== undefined && (await healthProfileRepository.find(userId, tx))) {
        await refreshEligibility(tx, userId);
      }
      const fields = [input.displayName !== undefined ? "displayName" : null, input.birthYear !== undefined ? "birthYear" : null].filter(
        (field): field is string => field !== null,
      );
      await recordAudit(tx, { userId, eventType: "profile_updated", metadata: { fields } });
    });
    return this.get(userId);
  },
};
