import { prisma } from "../../infrastructure/database/prisma.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { badRequest } from "../../shared/errors/app-error.ts";
import { consentService } from "../consent/consent.service.ts";
import { zonedToUtc } from "../medication/medication.model.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { datesBetween } from "../projections/daily-facts.model.ts";
import { expectedBuckets, freshness, HR_BUCKET_MINUTES, HR_METHODOLOGY, summarizeDay, type StoredBucket, type StoredResting } from "./heart-rate.model.ts";
import { addDays } from "./quality.model.ts";
import { SIMULATED_SOURCE } from "./simulation.ts";

const minutesOfDay = (t: string) => Number(t.slice(0, 2)) * 60 + Number(t.slice(3, 5));
const NOTICE = "Angka detak jantung dari perangkat bersifat deskriptif dan bukan diagnosis. Hari tanpa data bukan berarti tidak sehat.";

async function load(userId: string, from: string, to: string, timezone: string) {
  const lo = zonedToUtc(from, "00:00", timezone), hi = zonedToUtc(addDays(to, 1), "00:00", timezone);
  const [buckets, resting, prefs] = await Promise.all([
    prisma.wearableHeartRateBucket.findMany({ where: { userId, bucketStart: { gte: lo, lt: hi } }, orderBy: { bucketStart: "asc" }, select: { bucketStart: true, bpmMin: true, bpmMax: true, bpmAvg: true, sampleCount: true, dataOrigin: true, qualityStatus: true, source: true, deviceType: true } }),
    prisma.wearableRestingHeartRate.findMany({ where: { userId, measuredAt: { gte: lo, lt: hi } }, orderBy: { measuredAt: "asc" }, select: { measuredAt: true, bpm: true, dataOrigin: true, qualityStatus: true, source: true } }),
    prisma.deviceImportPreference.findUnique({ where: { userId } }),
  ]);
  return { buckets, resting, prefs };
}

const toStored = (b: Awaited<ReturnType<typeof load>>["buckets"][number]): StoredBucket => ({ bucketStart: b.bucketStart, bpmMin: b.bpmMin, bpmMax: b.bpmMax, bpmAvg: b.bpmAvg.toNumber(), sampleCount: b.sampleCount, dataOrigin: b.dataOrigin, qualityStatus: b.qualityStatus });
const toResting = (r: Awaited<ReturnType<typeof load>>["resting"][number]): StoredResting => ({ measuredAt: r.measuredAt, bpm: r.bpm, dataOrigin: r.dataOrigin, qualityStatus: r.qualityStatus });

export const heartRateService = {
  async summary(userId: string, days: number, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    const { timezone } = await preferencesService.get(userId);
    const local = localRecordTime(now, timezone);
    const today = local.localDate;
    const from = addDays(today, -(days - 1));
    const { buckets, resting, prefs } = await load(userId, from, today, timezone);
    const byDate = new Map<string, StoredBucket[]>();
    const restingByDate = new Map<string, StoredResting[]>();
    for (const b of buckets) {
      const d = localRecordTime(b.bucketStart, timezone).localDate;
      byDate.set(d, [...(byDate.get(d) ?? []), toStored(b)]);
    }
    for (const r of resting) {
      const d = localRecordTime(r.measuredAt, timezone).localDate;
      restingByDate.set(d, [...(restingByDate.get(d) ?? []), toResting(r)]);
    }
    const nowMinutes = minutesOfDay(local.localTime);
    const series = datesBetween(from, today).map((d) => summarizeDay(d, byDate.get(d) ?? [], restingByDate.get(d) ?? [], expectedBuckets(d, today, nowMinutes)));
    const lastBucket = buckets.at(-1);
    const lastResting = resting.at(-1);
    return {
      timezone,
      days,
      bucketMinutes: HR_BUCKET_MINUTES,
      methodology: HR_METHODOLOGY,
      enabled: { heartRate: Boolean(prefs?.heartRate), restingHeartRate: Boolean(prefs?.restingHeartRate) },
      series,
      latest: lastBucket ? { bpm: Math.round(lastBucket.bpmAvg.toNumber()), windowStart: lastBucket.bucketStart.toISOString(), windowMinutes: HR_BUCKET_MINUTES, sampleCount: lastBucket.sampleCount, dataOrigin: lastBucket.dataOrigin, deviceType: lastBucket.deviceType, simulated: lastBucket.source === SIMULATED_SOURCE } : null,
      restingLatest: lastResting ? { bpm: lastResting.bpm, measuredAt: lastResting.measuredAt.toISOString(), dataOrigin: lastResting.dataOrigin, simulated: lastResting.source === SIMULATED_SOURCE } : null,
      freshness: freshness(lastBucket?.bucketStart ?? null, now),
      simulated: buckets.some((b) => b.source === SIMULATED_SOURCE) || resting.some((r) => r.source === SIMULATED_SOURCE),
      notice: NOTICE,
    };
  },

  async day(userId: string, date: string, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    const { timezone } = await preferencesService.get(userId);
    const local = localRecordTime(now, timezone);
    if (date > local.localDate) throw badRequest("DATE_IN_FUTURE", "Tanggal belum terjadi.");
    const { buckets, resting } = await load(userId, date, date, timezone);
    const stored = buckets.map(toStored);
    const summary = summarizeDay(date, stored, resting.map(toResting), expectedBuckets(date, local.localDate, minutesOfDay(local.localTime)));
    return {
      timezone,
      date,
      bucketMinutes: HR_BUCKET_MINUTES,
      methodology: HR_METHODOLOGY,
      summary,
      buckets: buckets.map((b) => ({ start: b.bucketStart.toISOString(), min: b.bpmMin, max: b.bpmMax, avg: Math.round(b.bpmAvg.toNumber() * 10) / 10, sampleCount: b.sampleCount, dataOrigin: b.dataOrigin, deviceType: b.deviceType, needsReview: b.qualityStatus === "needs_review", simulated: b.source === SIMULATED_SOURCE })),
      resting: resting.map((r) => ({ measuredAt: r.measuredAt.toISOString(), bpm: r.bpm, dataOrigin: r.dataOrigin, needsReview: r.qualityStatus === "needs_review", simulated: r.source === SIMULATED_SOURCE })),
      notice: NOTICE,
    };
  },
};
