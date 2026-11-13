import { createHash } from "node:crypto";
import { prisma } from "../../../infrastructure/database/prisma.ts";
import { localRecordTime } from "../../../shared/http/record-schema.ts";
import { ACTIVITY_COUNTED_QUALITY } from "../../activity/activity.model.ts";
import { consentService } from "../../consent/consent.service.ts";
import { preferencesService } from "../../preferences/preferences.service.ts";
import { BASELINE_KEY, BASELINE_PRIOR, BASELINE_VERSION, bestSlot, buildFeatures, FEATURE_SCHEMA_VERSION, slotOfHour, type DayEvidence, type Slot } from "./behavior.model.ts";

const ARTIFACT = createHash("sha256").update(JSON.stringify({ BASELINE_KEY, BASELINE_VERSION, BASELINE_PRIOR, FEATURE_SCHEMA_VERSION })).digest("hex");
let cachedId: string | null = null;

async function modelId() {
  if (cachedId) return cachedId;
  const row = await prisma.modelVersion.upsert({
    where: { modelKey_version: { modelKey: BASELINE_KEY, version: BASELINE_VERSION } },
    create: { modelKey: BASELINE_KEY, version: BASELINE_VERSION, artifactSha256: ARTIFACT, featureSchemaVersion: FEATURE_SCHEMA_VERSION, status: "SHADOW", intendedUse: "Penilai deterministik slot waktu aktivitas; hanya dicatat dalam mode bayangan, tidak memengaruhi keputusan.", trainingDataProvenance: "Tidak dilatih. Laju historis per slot dengan pemulusan Beta(1,3) dari catatan pengguna sendiri.", evaluation: { status: "NOT_EVALUATED_ON_REAL_DATA" }, endpointRef: "in-process" },
    update: {},
  });
  cachedId = row.id;
  return row.id;
}

export const baselineService = {
  async evidence(userId: string, from: string, to: string, tz: string): Promise<DayEvidence[]> {
    const lo = new Date(Date.parse(from + "T00:00:00Z") - 86_400_000), hi = new Date(Date.parse(to + "T00:00:00Z") + 2 * 86_400_000);
    const sessions = await prisma.activitySession.findMany({ where: { userId, archivedAt: null, qualityStatus: { in: [...ACTIVITY_COUNTED_QUALITY] }, startedAt: { gte: lo, lt: hi } }, select: { startedAt: true } });
    const days = new Map<string, DayEvidence>();
    for (const s of sessions) {
      const t = localRecordTime(s.startedAt, tz);
      const slot = slotOfHour(Number(new Intl.DateTimeFormat("en-GB", { timeZone: tz, hour: "2-digit", hour12: false }).format(s.startedAt)) % 24);
      const d = days.get(t.localDate) ?? { localDate: t.localDate, slots: {}, observed: true };
      if (slot) d.slots[slot] = true;
      days.set(t.localDate, d);
    }
    return [...days.values()];
  },

  async shadowScore(userId: string, now = new Date()): Promise<{ slot: Slot; score: number } | null> {
    if (!(await consentService.hasConsent(userId, "personalized_ai"))) return null;
    const { timezone } = await preferencesService.get(userId);
    const today = localRecordTime(now, timezone).localDate;
    const from = new Date(Date.parse(today + "T00:00:00Z") - 28 * 86_400_000).toISOString().slice(0, 10);
    const t0 = Date.now();
    const rows = buildFeatures(userId, await this.evidence(userId, from, today, timezone), [], today, today);
    const best = bestSlot(rows);
    await prisma.mlInferenceRun.create({ data: { userId, modelVersionId: await modelId(), mode: "SHADOW", status: "OK", latencyMs: Date.now() - t0, inputBytes: JSON.stringify(rows).length, topLabel: best?.slot ?? null, topProbability: best ? Math.round(best.score * 10000) / 10000 : null } });
    return best;
  },
};
