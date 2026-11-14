import { prisma } from "../../infrastructure/database/prisma.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { consentService } from "../consent/consent.service.ts";
import { zonedToUtc } from "../medication/medication.model.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { HR_BUCKET_MINUTES, freshness } from "./heart-rate.model.ts";
import { addDays } from "./quality.model.ts";
import { SIMULATED_SOURCE } from "./simulation.ts";

export type MetricAvailability = "HAS_DATA" | "NO_DATA" | "NOT_ENABLED" | "PERMISSION_REQUIRED" | "STALE_DATA";

export const deviceTodayService = {
  async get(userId: string, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    const { timezone } = await preferencesService.get(userId);
    const today = localRecordTime(now, timezone).localDate;
    const lo = zonedToUtc(today, "00:00", timezone), hi = zonedToUtc(addDays(today, 1), "00:00", timezone);
    const [prefs, checkpoints, steps, sleep, workouts, hr, hrCount, resting] = await Promise.all([
      prisma.deviceImportPreference.findUnique({ where: { userId } }),
      prisma.deviceSyncCheckpoint.findMany({ where: { userId } }),
      prisma.dailySteps.findFirst({ where: { userId, localDate: { gte: new Date(addDays(today, -2) + "T00:00:00Z"), lte: new Date(today + "T00:00:00Z") } }, orderBy: { localDate: "desc" } }),
      prisma.sleepSession.findFirst({ where: { userId }, orderBy: { endedAt: "desc" } }),
      prisma.activitySession.findMany({ where: { userId, archivedAt: null, source: { not: "manual" }, startedAt: { gte: lo, lt: hi } }, select: { durationMinutes: true, source: true } }),
      prisma.wearableHeartRateBucket.findFirst({ where: { userId }, orderBy: { bucketStart: "desc" } }),
      prisma.wearableHeartRateBucket.count({ where: { userId, bucketStart: { gte: lo, lt: hi } } }),
      prisma.wearableRestingHeartRate.findFirst({ where: { userId }, orderBy: { measuredAt: "desc" } }),
    ]);
    const denied = checkpoints.some((c) => (c.lastErrorCode === "PERMISSION_DENIED" || c.lastErrorCode === "PERMISSION_REVOKED") && (!c.lastSuccessAt || (c.lastAttemptAt && c.lastAttemptAt > c.lastSuccessAt)));
    const state = (enabled: boolean, has: boolean, stale: boolean): MetricAvailability => (!enabled ? "NOT_ENABLED" : denied && !has ? "PERMISSION_REQUIRED" : !has ? "NO_DATA" : stale ? "STALE_DATA" : "HAS_DATA");
    const stepsDate = steps ? steps.localDate.toISOString().slice(0, 10) : null;
    return {
      date: today,
      timezone,
      steps: { availability: state(Boolean(prefs?.steps), Boolean(steps), stepsDate !== null && stepsDate !== today && stepsDate < addDays(today, -1)), value: steps ? { date: stepsDate, steps: steps.steps, dataOrigin: steps.dataOrigin, simulated: steps.source === SIMULATED_SOURCE } : null },
      heartRate: {
        availability: state(Boolean(prefs?.heartRate), Boolean(hr), freshness(hr?.bucketStart ?? null, now, 6) === "STALE"),
        value: hr ? { bpm: Math.round(hr.bpmAvg.toNumber()), windowStart: hr.bucketStart.toISOString(), windowMinutes: HR_BUCKET_MINUTES, todayBuckets: hrCount, restingBpm: resting?.bpm ?? null, dataOrigin: hr.dataOrigin, simulated: hr.source === SIMULATED_SOURCE } : null,
      },
      sleep: { availability: state(Boolean(prefs?.sleep), Boolean(sleep), sleep ? now.getTime() - sleep.endedAt.getTime() > 48 * 3_600_000 : false), value: sleep ? { startedAt: sleep.startedAt.toISOString(), endedAt: sleep.endedAt.toISOString(), durationMinutes: sleep.durationMinutes, dataOrigin: sleep.dataOrigin, simulated: sleep.source === SIMULATED_SOURCE } : null },
      activity: { availability: state(Boolean(prefs?.workouts), workouts.length > 0, false), value: workouts.length ? { sessions: workouts.length, minutes: workouts.reduce((s, w) => s + w.durationMinutes, 0), simulated: workouts.every((w) => w.source === SIMULATED_SOURCE) } : null },
      notice: "Nilai dari perangkat adalah perkiraan. Metrik tanpa data tidak diisi nol.",
    };
  },
};
