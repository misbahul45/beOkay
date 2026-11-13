import { prisma } from "../../infrastructure/database/prisma.ts";
import { AppError } from "../../shared/errors/app-error.ts";
import { JOURNEY_CAPABILITIES, JOURNEY_DESCRIPTIONS, JOURNEY_LABELS, JOURNEYS, type Journey, type JourneyCapabilities } from "./cohort.policy.ts";

export type ResolvedJourney = {
  journey: Journey;
  source: string;
  assumed: boolean;
  setAt: string | null;
  capabilities: JourneyCapabilities;
};

const asJourney = (v: string | null | undefined): Journey => ((JOURNEYS as readonly string[]).includes(v ?? "") ? (v as Journey) : "UNDETERMINED");

export const cohortService = {
  async resolve(userId: string): Promise<ResolvedJourney> {
    const row = await prisma.healthProfile.findUnique({ where: { userId }, select: { journey: true, journeySource: true, journeySetAt: true } });
    if (!row) return { journey: "T2DM_SUPPORT", source: "legacy_default", assumed: true, setAt: null, capabilities: JOURNEY_CAPABILITIES.T2DM_SUPPORT };
    const journey = asJourney(row.journey);
    return { journey, source: row.journeySource ?? "computed", assumed: false, setAt: row.journeySetAt?.toISOString() ?? null, capabilities: JOURNEY_CAPABILITIES[journey] };
  },

  async journeyOf(userId: string): Promise<Journey> {
    return (await this.resolve(userId)).journey;
  },

  async require(userId: string, capability: keyof JourneyCapabilities): Promise<ResolvedJourney> {
    const r = await this.resolve(userId);
    if (!r.capabilities[capability]) {
      throw new AppError(403, "JOURNEY_NOT_SUPPORTED", "Fitur ini belum tersedia untuk keadaanmu. Kamu tetap bisa mencatat dan melihat catatanmu.", { journey: r.journey, capability });
    }
    return r;
  },

  async view(userId: string) {
    const r = await this.resolve(userId);
    return { ...r, label: JOURNEY_LABELS[r.journey], description: JOURNEY_DESCRIPTIONS[r.journey] };
  },
};
