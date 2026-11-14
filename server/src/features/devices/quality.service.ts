import { prisma } from "../../infrastructure/database/prisma.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { consentService } from "../consent/consent.service.ts";
import { zonedToUtc } from "../medication/medication.model.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { datesBetween } from "../projections/daily-facts.model.ts";
import { freshness } from "./heart-rate.model.ts";
import { classifyProvenance, provenanceCounts, watchVerification, type Provenance } from "./provenance.ts";
import { addDays, assessHeartRate, assessSleep, assessSteps, assessWorkouts, type DayQuality, type HeartRateInput, QUALITY_VERSION, summarize, type Signal } from "./quality.model.ts";
import { SIMULATED_SOURCE } from "./simulation.ts";

const iso = (d: Date) => d.toISOString().slice(0, 10);
const STALE_HOURS = 48;
const PROVENANCE_WINDOW_DAYS = 30;
const iso0 = (d: Date | null) => d?.toISOString() ?? null;
const maxDate = (xs: (Date | null | undefined)[]) => {
  const ds = xs.filter((x): x is Date => Boolean(x));
  return ds.length ? new Date(Math.max(...ds.map((d) => d.getTime()))) : null;
};

type HeartRateRow = { local_date: Date; data_origin: string; buckets: number; samples: number; needs_review: boolean; synced_at: Date };

export const deviceQualityService = {
  async assess(userId: string, days = 14, now = new Date()) {
    const { timezone } = await preferencesService.get(userId);
    const today = localRecordTime(now, timezone).localDate;
    const from = addDays(today, -(days - 1));
    const lo = zonedToUtc(from, "00:00", timezone), hi = zonedToUtc(addDays(today, 1), "00:00", timezone);
    const [prefs, steps, sleep, workouts, hrRows] = await Promise.all([
      prisma.deviceImportPreference.findUnique({ where: { userId } }),
      prisma.dailySteps.findMany({ where: { userId, localDate: { gte: new Date(from + "T00:00:00Z"), lte: new Date(today + "T00:00:00Z") } } }),
      prisma.sleepSession.findMany({ where: { userId, endedAt: { gte: lo, lt: hi } } }),
      prisma.activitySession.findMany({ where: { userId, archivedAt: null, source: { not: "manual" }, startedAt: { gte: lo, lt: hi } } }),
      prisma.$queryRaw<HeartRateRow[]>`
        SELECT (bucket_start AT TIME ZONE ${timezone})::date AS local_date, data_origin, count(*)::int AS buckets, sum(sample_count)::int AS samples,
               bool_or(quality_status = 'needs_review') AS needs_review, max(updated_at) AS synced_at
        FROM wearable_heart_rate_buckets
        WHERE user_id = ${userId}::uuid AND bucket_start >= ${lo} AND bucket_start < ${hi}
        GROUP BY 1, 2`,
    ]);
    const lastSync = (xs: Date[]) => (xs.length ? new Date(Math.max(...xs.map((d) => d.getTime()))) : null);
    const lastSyncAt = {
      steps: lastSync(steps.map((s) => s.syncedAt)),
      sleep: lastSync(sleep.map((s) => s.updatedAt)),
      workouts: lastSync(workouts.map((w) => w.receivedAt)),
      heart_rate: lastSync(hrRows.map((r) => r.synced_at)),
    };
    const local = (d: Date) => localRecordTime(d, timezone).localDate;
    const dates = datesBetween(from, today);
    const perDay: Record<Signal, DayQuality[]> = { steps: [], sleep: [], workouts: [], heart_rate: [] };
    const hrByDate = new Map<string, HeartRateInput[]>();
    for (const r of hrRows) {
      const d = iso(r.local_date);
      const list = hrByDate.get(d) ?? [];
      list.push({ localDate: d, buckets: r.buckets, samples: r.samples, needsReview: r.needs_review, dataOrigin: r.data_origin, syncedAt: r.synced_at });
      hrByDate.set(d, list);
    }
    for (const d of dates) {
      perDay.steps.push(assessSteps(d, steps.filter((s) => iso(s.localDate) === d).map((s) => ({ localDate: d, steps: s.steps, dataOrigin: s.dataOrigin, syncedAt: s.syncedAt })), { today, now, connected: Boolean(prefs?.steps), lastSyncAt: lastSyncAt.steps }));
      perDay.sleep.push(assessSleep(d, sleep.filter((s) => local(s.endedAt) === d).map((s) => ({ startedAt: s.startedAt, endedAt: s.endedAt, dataOrigin: s.dataOrigin, createdAt: s.createdAt, localDate: d })), { today, now, connected: Boolean(prefs?.sleep), lastSyncAt: lastSyncAt.sleep }));
      perDay.workouts.push(assessWorkouts(d, workouts.filter((w) => local(w.startedAt) === d).map((w) => ({ startedAt: w.startedAt, durationMinutes: w.durationMinutes, dataOrigin: w.dataOrigin, receivedAt: w.receivedAt, qualityStatus: w.qualityStatus, localDate: d })), { today, now, connected: Boolean(prefs?.workouts), lastSyncAt: lastSyncAt.workouts }));
      perDay.heart_rate.push(assessHeartRate(d, hrByDate.get(d) ?? [], { today, now, connected: Boolean(prefs?.heartRate), lastSyncAt: lastSyncAt.heart_rate }));
    }
    return { version: QUALITY_VERSION, timezone, from, to: today, perDay, summary: (Object.keys(perDay) as Signal[]).map((s) => summarize(s, perDay[s])), lastSyncAt: { steps: iso0(lastSyncAt.steps), sleep: iso0(lastSyncAt.sleep), workouts: iso0(lastSyncAt.workouts), heart_rate: iso0(lastSyncAt.heart_rate) } };
  },

  async provenance(userId: string, now = new Date()) {
    const since = new Date(now.getTime() - PROVENANCE_WINDOW_DAYS * 86_400_000);
    const [hr, resting, sleep, workouts] = await Promise.all([
      prisma.wearableHeartRateBucket.groupBy({ by: ["source", "dataOrigin", "deviceType", "recordingMethod"], where: { userId, bucketStart: { gte: since } } }),
      prisma.wearableRestingHeartRate.groupBy({ by: ["source", "dataOrigin", "deviceType", "recordingMethod"], where: { userId, measuredAt: { gte: since } } }),
      prisma.sleepSession.groupBy({ by: ["source", "dataOrigin", "deviceType", "recordingMethod"], where: { userId, endedAt: { gte: since } } }),
      prisma.activitySession.groupBy({ by: ["source", "dataOrigin", "deviceType", "recordingMethod"], where: { userId, archivedAt: null, source: { not: "manual" }, startedAt: { gte: since } } }),
    ]);
    const groups = [...hr, ...resting, ...sleep, ...workouts].map((g) => ({ source: g.source, dataOrigin: g.dataOrigin, deviceType: g.deviceType, recordingMethod: g.recordingMethod }));
    const live = groups.filter((g) => g.source !== SIMULATED_SOURCE);
    const seen = new Set<string>();
    const sourceApplications: { dataOrigin: string; provenance: Provenance }[] = [];
    for (const g of groups) {
      if (!g.dataOrigin) continue;
      const provenance = classifyProvenance(g);
      const key = `${g.dataOrigin}|${provenance}`;
      if (seen.has(key)) continue;
      seen.add(key);
      sourceApplications.push({ dataOrigin: g.dataOrigin, provenance });
    }
    return {
      watchVerification: watchVerification(live),
      detectedDeviceTypes: [...new Set(live.map((g) => g.deviceType).filter((t): t is string => Boolean(t) && t !== "unknown"))].sort(),
      provenance: provenanceCounts(groups),
      sourceApplications: sourceApplications.sort((a, b) => a.dataOrigin.localeCompare(b.dataOrigin)),
      simulatedPresent: groups.some((g) => g.source === SIMULATED_SOURCE),
    };
  },

  async lastData(userId: string, timezone: string, now: Date) {
    const [steps, sleep, workout, hr, resting] = await Promise.all([
      prisma.dailySteps.findFirst({ where: { userId }, orderBy: { localDate: "desc" }, select: { localDate: true } }),
      prisma.sleepSession.findFirst({ where: { userId }, orderBy: { endedAt: "desc" }, select: { endedAt: true } }),
      prisma.activitySession.findFirst({ where: { userId, archivedAt: null, source: { not: "manual" } }, orderBy: { endedAt: "desc" }, select: { endedAt: true } }),
      prisma.wearableHeartRateBucket.findFirst({ where: { userId }, orderBy: { bucketStart: "desc" }, select: { bucketStart: true } }),
      prisma.wearableRestingHeartRate.findFirst({ where: { userId }, orderBy: { measuredAt: "desc" }, select: { measuredAt: true } }),
    ]);
    const today = localRecordTime(now, timezone).localDate;
    const daysAgo = (d: string) => (Date.parse(today + "T00:00:00Z") - Date.parse(d + "T00:00:00Z")) / 86_400_000;
    const stepsDate = steps ? iso(steps.localDate) : null;
    const entry = (metric: string, at: Date | null) => ({ metric, lastDataAt: iso0(at), lastDataDate: null as string | null, freshness: freshness(at, now, STALE_HOURS) });
    const metricFreshness = [
      { metric: "steps", lastDataAt: null as string | null, lastDataDate: stepsDate, freshness: (stepsDate === null ? "NO_DATA" : daysAgo(stepsDate) > STALE_HOURS / 24 ? "STALE" : "FRESH") as "NO_DATA" | "FRESH" | "STALE" },
      entry("sleep", sleep?.endedAt ?? null),
      entry("workouts", workout?.endedAt ?? null),
      entry("heart_rate", hr?.bucketStart ?? null),
      entry("resting_heart_rate", resting?.measuredAt ?? null),
    ];
    return { lastDataAt: iso0(maxDate([sleep?.endedAt, workout?.endedAt, hr?.bucketStart, resting?.measuredAt])), metricFreshness };
  },

  async status(userId: string, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    const [q, prefs, deviceConsent, checkpoints, prov] = await Promise.all([
      this.assess(userId, 14, now),
      prisma.deviceImportPreference.findUnique({ where: { userId } }),
      consentService.hasConsent(userId, "device_data_coaching"),
      prisma.deviceSyncCheckpoint.findMany({ where: { userId } }),
      this.provenance(userId, now),
    ]);
    const data = await this.lastData(userId, q.timezone, now);
    const origins = [...new Set(Object.values(q.perDay).flat().flatMap((d) => d.origins))].filter((o) => o !== "unknown").sort();
    const permissions = { workouts: Boolean(prefs?.workouts), steps: Boolean(prefs?.steps), weight: Boolean(prefs?.weight), glucose: Boolean(prefs?.glucose), sleep: Boolean(prefs?.sleep), heartRate: Boolean(prefs?.heartRate), restingHeartRate: Boolean(prefs?.restingHeartRate) };
    const lastAttempt = maxDate(checkpoints.map((c) => c.lastAttemptAt));
    const lastSuccess = maxDate(checkpoints.map((c) => c.lastSuccessAt));
    const failing = checkpoints.filter((c) => c.lastErrorCode && (!c.lastSuccessAt || (c.lastAttemptAt && c.lastAttemptAt > c.lastSuccessAt)));
    const syncState = !Object.values(permissions).some(Boolean)
      ? "IMPORT_DISABLED"
      : failing.length
        ? "SYNC_FAILED"
        : !lastSuccess
          ? "NEVER_SYNCED"
          : now.getTime() - lastSuccess.getTime() > STALE_HOURS * 3_600_000
            ? "SYNC_STALE"
            : "OK";
    const errorCodes = new Set(failing.map((c) => c.lastErrorCode));
    const permissionState = errorCodes.has("PERMISSION_REVOKED") ? "PERMISSION_REVOKED" : errorCodes.has("PERMISSION_DENIED") ? "PERMISSION_DENIED" : "UNKNOWN";
    const healthConnectAvailability = errorCodes.has("HEALTH_CONNECT_INSTALL_REQUIRED") ? "HEALTH_CONNECT_INSTALL_REQUIRED" : errorCodes.has("HEALTH_CONNECT_UNAVAILABLE") ? "HEALTH_CONNECT_UNAVAILABLE" : "UNKNOWN";
    const sourceCoverage = q.summary.map((s) => {
      const counts = new Map<string, number>();
      for (const d of q.perDay[s.signal]) for (const o of d.origins) counts.set(o, (counts.get(o) ?? 0) + 1);
      return { signal: s.signal, origins: [...counts.entries()].map(([origin, days]) => ({ origin, days })).sort((a, b) => a.origin.localeCompare(b.origin)) };
    });
    return {
      version: q.version,
      window: { from: q.from, to: q.to, timezone: q.timezone },
      permissions,
      enabledMetrics: Object.entries(permissions).filter(([, v]) => v).map(([k]) => k),
      usedForCoaching: deviceConsent,
      lastSyncAt: q.lastSyncAt,
      lastSyncAttemptAt: iso0(lastAttempt),
      lastSuccessfulSyncAt: iso0(lastSuccess),
      lastDataAt: data.lastDataAt,
      syncState,
      healthConnectAvailability,
      permissionState,
      lastErrorCodes: [...errorCodes],
      metricFreshness: data.metricFreshness,
      metricQuality: q.summary,
      sourceCoverage,
      origins,
      sourceApplications: prov.sourceApplications,
      detectedDeviceTypes: prov.detectedDeviceTypes,
      provenance: prov.provenance,
      watchVerification: prov.watchVerification,
      simulated: prov.simulatedPresent,
      signals: q.summary,
      days: q.perDay,
      notice: "Hari tanpa data perangkat tidak pernah dianggap tidak aktif. Angka dari perangkat adalah perkiraan.",
      connectionNotice: "Data dari Health Connect tidak membuktikan jam tangan terpasang. Status jam tangan hanya naik bila sumber data menyatakannya.",
    };
  },
};
